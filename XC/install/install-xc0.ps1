Param(
    [string] $ConfigurationFile = '.\configuration-xc0.json',
    [switch] $SkipHabitatHomeInstall
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#####################################################
#
#  Install Sitecore
#
#####################################################
$ErrorActionPreference = 'Stop'
#Set-Location $PSScriptRoot


if (!(Test-Path $ConfigurationFile)) {
    Write-Host 'Configuration file '$($ConfigurationFile)' not found.' -ForegroundColor Red
    Write-Host  'Please use 'set-installation...ps1' files to generate a configuration file.' -ForegroundColor Red
    Exit 1
}

$config = Get-Content -Raw $ConfigurationFile -Encoding Ascii | ConvertFrom-Json

if (!$config) {
    throw "Error trying to load configuration!"
}

$site = $config.settings.site
$commerceAssets = $config.assets.commerce
$sql = $config.settings.sql
$xConnect = $config.settings.xConnect
$sitecore = $config.settings.sitecore
$identityServer = $config.settings.identityServer
$solr = $config.settings.solr
$assets = $config.assets
$commerce = $config.settings.commerce
$resourcePath = Join-Path $assets.root "Resources"
$publishPath = Join-Path $resourcePath "Publish"
$sharedResourcePath = Join-Path $assets.sharedUtilitiesRoot "assets"


Write-Host "*******************************************************" -ForegroundColor Green
Write-Host " Installing Commerce $($assets.commerce.packageVersion)" -ForegroundColor Green
Write-Host " Sitecore: $($site.hostName)" -ForegroundColor Green
Write-Host " Storefront $($site.storefrontHostName)" -ForegroundColor Green
Write-Host " xConnect: $($xConnect.siteName)" -ForegroundColor Green
Write-Host "*******************************************************" -ForegroundColor Green

function Get-SitecoreCredentials {

    if ($null -eq $global:credentials) {
        if ([string]::IsNullOrEmpty($devSitecoreUsername)) {
            $global:credentials = Get-Credential -Message "Please provide dev.sitecore.com credentials"
        }
        elseif (![string]::IsNullOrEmpty($devSitecoreUsername) -and ![string]::IsNullOrEmpty($devSitecorePassword)) {
            $secpasswd = ConvertTo-SecureString $devSitecorePassword -AsPlainText -Force
            $global:credentials = New-Object System.Management.Automation.PSCredential ($devSitecoreUsername, $secpasswd)
        }
        else {
            throw "Credentials required for download"
        }
    }
    $user = $global:credentials.GetNetworkCredential().UserName
    $password = $global:credentials.GetNetworkCredential().Password

    Invoke-RestMethod -Uri https://dev.sitecore.net/api/authorization -Method Post -ContentType "application/json" -Body "{username: '$user', password: '$password'}" -SessionVariable loginSession -UseBasicParsing
    $global:loginSession = $loginSession

}
function Install-RequiredInstallationAssets {
    #Register Assets PowerShell Repository
    if ((Get-PSRepository | Where-Object { $_.Name -eq $assets.psRepositoryName }).count -eq 0) {
        Register-PSRepository -Name $AssetsPSRepositoryName -SourceLocation $assets.psRepository -InstallationPolicy Trusted
    }

    #Sitecore Install Framework dependencies
    Import-Module WebAdministration

    #Install SIF
    $module = Get-Module -FullyQualifiedName @{ModuleName = "SitecoreInstallFramework"; ModuleVersion = $assets.installerVersion }
    if (-not $module) {
        write-host "Installing the Sitecore Install Framework, version $($assets.installerVersion)" -ForegroundColor Green
        Install-Module SitecoreInstallFramework -RequiredVersion $assets.installerVersion -Repository $assets.psRepositoryName -Scope CurrentUser
    }
    Import-Module SitecoreInstallFramework -RequiredVersion $assets.installerVersion -Force
    #Verify that manual assets are present
    if (!(Test-Path $assets.root)) {
        throw "$($assets.root) not found"
    }

}
function Install-CommerceAssets {
    Set-Location $PSScriptRoot

    $commercePackageDestination = Join-Path $assets.downloadFolder $assets.commerce.packageName

    if (!(Test-Path $commercePackageDestination)) {
        Get-SitecoreCredentials
        $params = @{
            Path         = $([io.path]::combine($sharedResourcePath, 'configuration\download-assets.json'))
            LoginSession = $global:loginSession
            Source       = $assets.commerce.packageUrl
            Destination  = $commercePackageDestination
        }
        $Global:ProgressPreference = 'SilentlyContinue'
        Install-SitecoreConfiguration  @params  -WorkingDirectory $(Join-Path $PWD "logs") -Verbose
        $Global:ProgressPreference = 'Continue'

    }

    $msbuildNuGetUrl = "https://www.nuget.org/api/v2/package/MSBuild.Microsoft.VisualStudio.Web.targets/14.0.0.3"
    $msbuildNuGetPackageFileName = "msbuild.microsoft.visualstudio.web.targets.14.0.0.3.nupkg"
    $msbuildNuGetPackageDestination = $([io.path]::combine($assets.downloadFolder, $msbuildNuGetPackageFileName))

    if (!(Test-Path $msbuildNuGetPackageDestination)) {
        Write-Host "Saving $msbuildNuGetUrl to $msbuildNuGetPackageDestination" -ForegroundColor Green
        Get-SitecoreCredentials
        $params = @{
            Path         = $([io.path]::combine($sharedResourcePath, 'configuration\download-assets.json'))
            LoginSession = $global:loginSession
            Source       = $msbuildNuGetUrl
            Destination  = $msbuildNuGetPackageDestination
        }
        Install-SitecoreConfiguration  @params  -WorkingDirectory $(Join-Path $PWD "logs") -Verbose
    }

    $commerceAssetFolder = $assets.commerce.installationFolder

    if (!(Test-Path $commerceAssetFolder)) {
        New-Item -ItemType Directory -Path $commerceAssetFolder
    }

    $habitatHomeImagePackageUrl = "https://sitecore.box.com/shared/static/acv0qhew42m2653qtg2s7qlxlrmqjfpe.zip"
    $habitatHomeImagePackageFileName = "Habitat Home Product Images.zip"
    $habitatHomeImagePackageDestination = (Join-Path $CommerceAssetFolder $habitatHomeImagePackageFileName)

    Get-SitecoreCredentials

    if (!(Test-Path $habitatHomeImagePackageDestination)) {
        Write-Host ("Saving '{0}' to '{1}'" -f $habitatHomeImagePackageFileName, $habitatHomeImagePackageDestination) -ForegroundColor Green
        $params = @{
            Path         = $([io.path]::combine($sharedResourcePath, 'configuration\download-assets.json'))
            LoginSession = $global:loginSession
            Source       = $habitatHomeImagePackageUrl
            Destination  = $habitatHomeImagePackageDestination
        }
        $Global:ProgressPreference = 'SilentlyContinue'
        Install-SitecoreConfiguration  @params -WorkingDirectory $(Join-Path $PWD "logs") -Verbose
        $Global:ProgressPreference = 'Continue'

    }
    Write-Host "Extracting to $($CommerceAssetFolder)"
    set-alias sz "$env:ProgramFiles\7-zip\7z.exe"

    sz x -o"$commerceAssetFolder" $commercePackageDestination -r -y -aoa

    # This is where we expand the archives:
    $packagesToExtract = $assets.commerce.filesToExtract

    foreach ($package in $packagesToExtract) {

        $extract = Join-Path $assets.commerce.installationFolder $($package.name + "." + $package.version + ".zip")
        $output = Join-Path $assets.commerce.installationFolder $($package.name + "." + $package.version)

        sz x -o"$($output)" $extract -r -y -aoa
    }
    # Extract MSBuild nuget package
    $extract = $(Join-Path $assets.downloadFolder "msbuild.microsoft.visualstudio.web.targets.14.0.0.3.nupkg")
    $output = $(Join-Path $assets.commerce.installationFolder "msbuild.microsoft.visualstudio.web.targets.14.0.0.3")
    sz x -o"$($output)" $extract -r -y -aoa
}

Function Start-Site {
    $Hostname = "$($site.hostName)"

    $R = try { Invoke-WebRequest "https://$Hostname/sitecore/login" -ea SilentlyContinue } catch { }
    while (!$R) {

        Start-Sleep 30
        Write-Output "Waiting for Sitecore to start up..."
        $R = try { Invoke-WebRequest "https://$Hostname/sitecore/login" -ea SilentlyContinue } catch { }
    }

}
Function Set-ModulesPath {
    Write-Host "Setting Modules Path" -ForegroundColor Green
    $modulesPath = ( Join-Path -Path $resourcePath -ChildPath "Modules" )
    if ($env:PSModulePath -notlike "*$modulesPath*") {
        $p = $env:PSModulePath + ";" + $modulesPath
        [Environment]::SetEnvironmentVariable("PSModulePath", $p)
    }
}

Function Publish-CommerceEngine {
    Write-Host "Publishing Commerce Engine" -ForegroundColor Green
    $SolutionName = Join-Path "..\" "HabitatHome.Commerce.Engine.sln"
    $PublishLocation = Join-Path $($publishPath + "\")  $($site.prefix + ".Commerce.Engine")
    if (Test-Path $PublishLocation) {
        Remove-Item $PublishLocation -Force -Recurse
    }

    if (Test-Path $SolutionName) {
        dotnet publish $SolutionName -o $publishLocation
    }
    else {
        $commerceEngine = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "Sitecore.Commerce.Engine" }
        $commerceEngineSource = Join-Path $commerceAssets.installationFolder $($commerceEngine.name + "." + $commerceEngine.version + "/")
        Copy-Item -Path $commerceEngineSource -Destination $PublishLocation  -Force -Recurse
    }
}


Function Publish-BizFx {
    Write-Host "Publishing BizFx" -ForegroundColor Green
    $bizFx = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "Sitecore.BizFX" }
    $bizFxSource = Join-Path $commerceAssets.installationFolder $($bizFx.name + "." + $bizFx.version + "/")

    $PublishLocation = Join-Path $publishPath $($site.prefix + ".Commerce.BizFx")
    if (Test-Path $PublishLocation) {
        Remove-Item $PublishLocation -Force -Recurse
    }
    Copy-Item -Path $bizFxSource -Destination $PublishLocation  -Force -Recurse
}
Function Convert-Modules {
    $sat = Join-Path $assets.sitecoreazuretoolkit "tools\Sitecore.Cloud.Cmdlets.dll"
    Import-Module $sat -Force

    $modules = @{
        # AdventureWorksImagesModuleFullPath = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Adventure Works Images.zip" -Exclude "*.scwdp.zip" -Recurse  )
        # CommerceConnectModuleFullPath      = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce Connect*.zip" -Exclude "*.scwdp.zip" -Recurse  )
        # CommercexProfilesModuleFullPath    = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce ExperienceProfile Core *.zip" -Exclude "*.scwdp.zip" -Recurse)
        # CommercexAnalyticsModuleFullPath   = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce ExperienceAnalytics Core *.zip"	-Exclude "*.scwdp.zip" -Recurse)
        # CommerceMAModuleFullPath           = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce Marketing Automation Core *.zip"	-Exclude "*.scwdp.zip" -Recurse)
        # CEConnectModuleFullPath            = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Engine Connect*.zip" -Exclude "*.scwdp.zip" -Recurse)
        # SXACommerceModuleFullPath          = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Experience Accelerator 2.*.zip" -Exclude "*.scwdp.zip" -Recurse)
        # SXAStorefrontModuleFullPath        = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Experience Accelerator Storefront 2.*.zip"-Exclude "*.scwdp.zip" -Recurse )
        # SXAStorefrontThemeModuleFullPath   = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Experience Accelerator Storefront Themes*.zip"-Exclude "*.scwdp.zip" -Recurse )
        # SXAStorefrontCatalogModuleFullPath = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Experience Accelerator Habitat Catalog*.zip" -Exclude "*.scwdp.zip" -Recurse)
        HabitatImagesModuleFullPath = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Habitat Home Product Images.zip" -Exclude "*.scwdp.zip" -Recurse)
    }
    foreach ($key in $modules.Keys) {

        if (!(Test-Path ($modules[$key] -replace ".zip", ".scwdp.zip"))) {
            Write-Host "Converting module: $modules[$key]" -ForegroundColor Green
            ConvertTo-SCModuleWebDeployPackage -Path $modules[$key] -Destination $assets.commerce.installationFolder -Verbose -Force
        }
    }
}

Function Install-Commerce {
    Write-Host "Installing Commerce" -ForegroundColor Green
    $configurationDir = "$PWD\assets\resources\Configuration"
    Remove-Item "$configurationDir\Commerce\*" -include *.json -exclude Master_SingleServer.json
    Get-ChildItem $configurationDir -exclude 'Master_SingleServer.json' -Include *.json -Recurse | Copy-Item -Destination "$configurationDir\Commerce"

    $params = @{
        Path                                     = $(Join-Path $configurationDir  'Master_SingleServer.json')
        SiteName                                 = $site.hostName
        SiteHostHeaderName                       = $commerce.storefrontHostName
        InstallDir                               = $(Join-Path $site.webRoot $site.hostName)
        XConnectInstallDir                       = $xConnect.siteRoot
        SiteUtilitiesSrc                         = $(Join-Path -Path $assets.commerce.sifCommerceRoot -ChildPath "SiteUtilityPages")
        SitecoreIdentityServerApplicationName    = $identityServer.name
        SitecoreIdentityServerUrl                = $identityServer.url
        SkipInstallDefaultStorefront             = $false
        CommerceSearchProvider                   = "solr"
        SolrUrl                                  = $solr.url
        SolrRoot                                 = $solr.root
        SolrService                              = $solr.serviceName
        SolrSchemas                              = (Join-Path -Path $assets.commerce.sifCommerceRoot -ChildPath "SolrSchemas" )
        SearchIndexPrefix                        = $site.prefix
        AzureSearchServiceName                   = ""
        AzureSearchAdminKey                      = ""
        AzureSearchQueryKey                      = ""
        CommerceEngineCertificateName            = $site.prefix + "storefront.engine"
        CommerceEngineWdpFullPath                = $(Get-ChildItem -Path $assets.commerce.installationFolder -Include "Sitecore.Commerce.Engine.OnPrem.Solr*scwdp.zip" -Recurse)
        CommerceServicesDbServer                 = $sql.server
        CommerceServicesDbName                   = $($site.prefix + "_SharedEnvironments")
        CommerceServicesGlobalDbName             = $($site.prefix + "_Global")
        CommerceServicesHostPostfix              = $site.hostName
        CommerceServicesPostfix                  = $site.prefix
        CommerceOpsServicesPort                  = "5015"
        CommerceShopsServicesPort                = "5005"
        CommerceAuthoringServicesPort            = "5000"
        CommerceMinionsServicesPort              = "5010"
        CommerceInstallRoot                      = $site.webRoot
        EnvironmentsPrefix                       = $site.prefix
        Environments                             = @('HabitatAuthoring')
        MinionEnvironments                       = @('HabitatMinions')
        EnvironmentsGuids                        = @('40e77b7b4be94186b53b5bfd89a6a83b')
        SitecoreDbServer                         = $sql.server
        SitecoreCoreDbName                       = $($site.prefix + "_Core")
        SqlDbPrefix                              = $site.prefix
        SqlAdminPassword                         = $sql.adminPassword
        SqlAdminUser                             = $sql.adminUser
        UserDomain                               = $commerce.serviceAccountDomain
        UserName                                 = $commerce.serviceAccountUserName
        UserPassword                             = $commerce.serviceAccountPassword
        RedisConfiguration                       = "localhost"
        RedisInstanceName                        = "Redis"
        RedisInstallationPath                    = "C:\Program Files\Redis"
        HabitatImagesWdpFullPath                 = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Habitat Home Product Images.scwdp.zip" -Recurse)
        AdventureWorksImagesWdpFullPath          = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Adventure Works Images.OnPrem*.scwdp.zip" -Recurse)
        CommerceConnectWdpFullPath               = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce Connect Core*.scwdp.zip" -Recurse  )
        CommercexProfilesWdpFullPath             = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce ExperienceProfile Core *.scwdp.zip" -Recurse)
        CommercexAnalyticsWdpFullPath            = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce ExperienceAnalytics Core *.scwdp.zip"	-Recurse)
        CommerceMAWdpFullPath                    = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce Marketing Automation Core *.scwdp.zip"	-Recurse)
        CommerceMAForAutomationEngineWdpFullPath = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce Marketing Automation for AutomationEngine *.zip"	-Recurse)
        CEConnectWdpFullPath                     = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Engine Connect*.scwdp.zip" -Recurse)
        SXACommerceWdpFullPath                   = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Experience Accelerator 3*.scwdp.zip" -Recurse)
        SXAStorefrontWdpFullPath                 = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Experience Accelerator Storefront 3*.scwdp.zip"-Recurse )
        SXAStorefrontThemeWdpFullPath            = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Experience Accelerator Storefront Themes*.scwdp.zip"-Recurse )
        SXAStorefrontCatalogWdpFullPath          = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Experience Accelerator Habitat Catalog*.scwdp.zip" -Recurse)
        MergeToolFullPath                        = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "*Microsoft.Web.XmlTransform.dll" -Recurse | Select-Object -ExpandProperty FullName)
        SitecoreDomain                           = "sitecore"
        SitecoreUsername                         = "admin"
        SitecoreUserPassword                     = $sitecore.adminPassword
        BraintreeMerchantId                      = $commerce.brainTreeAccountMerchandId
        BraintreePrivateKey                      = $commerce.brainTreeAccountPrivateKey
        BraintreePublicKey                       = $commerce.brainTreeAccountPublicKey
        BizFxSiteName                            = "SitecoreBizFx"
        BizFxPort                                = "4200"
        BizFxPackage                             = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore.BizFx.OnPrem*.scwdp.zip" -Recurse)
    }

    Import-Module (Join-Path $assets.sharedUtilitiesRoot "assets\modules\SharedInstallationUtilities\SharedInstallationUtilities.psm1") -Verbose -Force

    Push-Location $resourcePath
    If (!$SkipHabitatHomeInstall) {
        Install-SitecoreConfiguration @params  -Verbose
    }
    Else {
        Install-SitecoreConfiguration @params -Skip "InitializeCommerceEngine", "GenerateCatalogTemplates", "InstallHabitatImagesModule", "Reindex" -Verbose *>&1 | Tee-Object "logs\output.log"
    }
}
Pop-Location

$StopWatch = New-Object -TypeName System.Diagnostics.Stopwatch
$StopWatch.Start()

#Install-RequiredInstallationAssets
#Set-ModulesPath
#Install-CommerceAssets
#Publish-CommerceEngine
#Publish-BizFx
#Convert-Modules
Install-Commerce
Start-Site

$StopWatch.Stop()
$StopWatch
