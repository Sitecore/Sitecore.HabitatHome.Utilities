Param(
    [string] $ConfigurationFile = '.\configuration-xc0.json',
    [switch] $SkipHabitatHomeInstall
)

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

$config = Get-Content -Raw $ConfigurationFile -Encoding Ascii |  ConvertFrom-Json

if (!$config) {
    throw "Error trying to load configuration!"
}

$site = $config.settings.site
$commerceAssets = $config.assets.commerce
$sql = $config.settings.sql
$xConnect = $config.settings.xConnect
$sitecore = $config.settings.sitecore
$solr = $config.settings.solr
$assets = $config.assets
$commerce = $config.settings.commerce
$resourcePath = Join-Path $assets.root "Resources"
$publishPath = Join-Path $resourcePath "Publish"

Write-Host "*******************************************************" -ForegroundColor Green
Write-Host " Installing Commerce $($assets.commerce.packageVersion)" -ForegroundColor Green
Write-Host " Sitecore: $($site.hostName)" -ForegroundColor Green
Write-Host " Storefront $($site.storefrontHostName)" -ForegroundColor Green
Write-Host " xConnect: $($xConnect.siteName)" -ForegroundColor Green
Write-Host "*******************************************************" -ForegroundColor Green


function Install-RequiredInstallationAssets {
    #Register Assets PowerShell Repository
    if ((Get-PSRepository | Where-Object {$_.Name -eq $assets.psRepositoryName}).count -eq 0) {
        Register-PSRepository -Name $AssetsPSRepositoryName -SourceLocation $assets.psRepository -InstallationPolicy Trusted
    }

    #Sitecore Install Framework dependencies
    Import-Module WebAdministration

    #Install SIF
    $module = Get-Module -FullyQualifiedName @{ModuleName = "SitecoreInstallFramework"; ModuleVersion = $assets.installerVersion}
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

    $loginRequest = Invoke-RestMethod -Uri https://dev.sitecore.net/api/authorization -Method Post -ContentType "application/json" -Body "{username: '$user', password: '$password'}" -SessionVariable loginSession -UseBasicParsing 

    
    $commercePackageDestination = Join-Path $assets.downloadFolder $assets.commerce.packageName

    if (!(Test-Path $commercePackageDestination)) {
	
        $credentials = Get-Credential -Message "Please provide dev.sitecore.com credentials"

        $params = @{
            Path         = $([io.path]::combine($resourcePath, 'configuration', 'commerce', 'HabitatHome', 'download-assets.json'))
            LoginSession = $loginSession
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
        $params = @{
            Path         = $([io.path]::combine($resourcePath, 'configuration', 'commerce', 'HabitatHome', 'download-assets.json'))
            LoginSession = $loginSession
            Source       = $msbuildNuGetUrl
            Destination  = $msbuildNuGetPackageDestination
        }
        Install-SitecoreConfiguration  @params  -WorkingDirectory $(Join-Path $PWD "logs") -Verbose 
    }
    
    $commerceAssetFolder = $assets.commerce.installationFolder

    $habitatHomeImagePackageUrl = "https://sitecore.box.com/shared/static/bjvge68eqge87su5vg258366rve6bg5d.zip"
    $habitatHomeImagePackageFileName = "Habitat Home Product Images.zip"
    $habitatHomeImagePackageDestination = (Join-Path $CommerceAssetFolder $habitatHomeImagePackageFileName)


    if (!(Test-Path $habitatHomeImagePackageDestination)) {
        Write-Host ("Saving '{0}' to '{1}'" -f $habitatHomeImagePackageFileName, $habitatHomeImagePackageDestination) -ForegroundColor Green
        $params = @{
            Path         = $([io.path]::combine($resourcePath, 'configuration', 'commerce', 'HabitatHome', 'download-assets.json'))
            LoginSession = $loginSession
            Source       = $habitatHomeImagePackageUrl
            Destination  = $habitatHomeImagePackageDestination
        }
        $Global:ProgressPreference = 'SilentlyContinue'
        Install-SitecoreConfiguration  @params  -WorkingDirectory $(Join-Path $PWD "logs") -Verbose 
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

        if ($package.name -eq "Sitecore.Commerce.Engine.SDK") {
            sz e $extract -o"$($assets.commerce.installationFolder)" "Sitecore.Commerce.Engine.DB.dacpac" -y -aoa
        }
        else {
            sz x -o"$($output)" $extract -r -y -aoa
        }
    }
    # Extract MSBuild nuget package
    $extract = $(Join-Path $assets.downloadFolder "msbuild.microsoft.visualstudio.web.targets.14.0.0.3.nupkg")
    $output = $(Join-Path $assets.commerce.installationFolder "msbuild.microsoft.visualstudio.web.targets.14.0.0.3")
    sz x -o"$($output)" $extract -r -y -aoa
}
Function Stop-XConnect {
    $params = @{
        Path     = $(Join-Path $resourcePath "stop-site.json")
        SiteName = $xConnect.siteName
    }
    Install-SitecoreConfiguration  @params -WorkingDirectory $(Join-Path $PWD "logs")
}
Function Start-XConnect {
    $params = @{
        Path     = $(Join-Path $resourcePath "start-site.json")
        SiteName = $xConnect.siteName
    }
    Install-SitecoreConfiguration  @params -WorkingDirectory $(Join-Path $PWD "logs")
}
Function Start-Site {
    $Hostname = "$($site.hostName)"

    $R = try { Invoke-WebRequest "https://$Hostname/sitecore/login" -ea SilentlyContinue } catch {}
    while (!$R) {

        Start-Sleep 30
        Write-Output "Waiting for Sitecore to start up..."
        $R = try { Invoke-WebRequest "https://$Hostname/sitecore/login" -ea SilentlyContinue } catch {}
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
        $commerceEngine = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "Sitecore.Commerce.Engine"}
        $commerceEngineSource = Join-Path $commerceAssets.installationFolder $($commerceEngine.name + "." + $commerceEngine.version + "/")
        Copy-Item -Path $commerceEngineSource -Destination $PublishLocation  -Force -Recurse
    }
}

Function Publish-IdentityServer {
    Write-Host "Publishing IdentityServer" -ForegroundColor Green
    $identityServer = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "Sitecore.IdentityServer"} 
    $identityServerSource = Join-Path $commerceAssets.installationFolder $($identityServer.name + "." + $identityServer.version + "/")
    $PublishLocation = Join-Path $publishPath $($site.prefix + ".Commerce.IdentityServer")

    if (Test-Path $PublishLocation) {
        Remove-Item $PublishLocation -Force -Recurse
    }
    Copy-Item -Path $identityServerSource -Destination $PublishLocation  -Force -Recurse
}
Function Publish-BizFx {
    Write-Host "Publishing BizFx" -ForegroundColor Green
    $bizFx = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "Sitecore.BizFX"}
    $bizFxSource = Join-Path $commerceAssets.installationFolder $($bizFx.name + "." + $bizFx.version + "/")

    $PublishLocation = Join-Path $publishPath $($site.prefix + ".Commerce.BizFx")
    if (Test-Path $PublishLocation) {
        Remove-Item $PublishLocation -Force -Recurse
    }
    Copy-Item -Path $bizFxSource -Destination $PublishLocation  -Force -Recurse
}
Function Install-Commerce {
    Write-Host "Installing Commerce" -ForegroundColor Green
    $params = @{
        Path                                        = $(Join-Path $resourcePath  'Commerce_SingleServer.json')
        BaseConfigurationFolder                     = $(Join-Path $resourcePath "Configuration")
        CommerceInstallRoot                         = $site.webRoot
        CommerceServicesPostfix                     = $site.prefix
        Environments                                = @('Habitat_Authoring')
        EnvironmentsPrefix                          = $site.prefix
        SiteName                                    = $site.hostName
        SiteHostHeaderName                          = $commerce.storefrontHostName
        InstallDir                                  = $(Join-Path $site.webRoot $site.hostName)
        XConnectInstallDir                          = $xConnect.siteRoot
        RootCertFileName                            = $sitecore.rootCertificateName
        CommerceServicesDbServer                    = $sql.server
        CommerceServicesDbName                      = $($site.prefix + "_SharedEnvironments")
        CommerceServicesGlobalDbName                = $($site.prefix + "_Global")
        SitecoreDbServer                            = $sql.server
        SitecoreCoreDbName                          = $($site.prefix + "_Core")
        SitecoreUsername                            = "sitecore\admin"
        SitecoreUserPassword                        = $sitecore.adminPassword
        CommerceSearchProvider                      = "solr"
        SolrUrl                                     = $solr.url
        SolrRoot                                    = $solr.root
        SolrService                                 = $solr.serviceName
        SolrSchemas                                 = (Join-Path -Path $assets.commerce.sifCommerceRoot -ChildPath "SolrSchemas" )
        SearchIndexPrefix                           = $site.prefix
        AzureSearchServiceName                      = ""
        AzureSearchAdminKey                         = ""
        AzureSearchQueryKey                         = ""
        CommerceEngineDacPac                        = (Join-Path $assets.commerce.installationFolder  "Sitecore.Commerce.Engine.DB.dacpac")
        CommerceOpsServicesPort                     = "5015"
        CommerceShopsServicesPort                   = "5005"
        CommerceAuthoringServicesPort               = "5000"
        CommerceMinionsServicesPort                 = "5010"
        SitecoreBizFxPort                           = "4200"
        SitecoreCommerceEnginePath                  = $($publishPath + "\" + $site.prefix + ".Commerce.Engine")
        SitecoreBizFxServicesContentPath            = $($publishPath + "\" + $site.prefix + ".Commerce.BizFX")
        SitecoreIdentityServerPath                  = $($publishPath + "\" + $site.prefix + ".Commerce.IdentityServer")
        CommerceEngineCertificatePath               = $(Join-Path -Path $assets.certificatesPath -ChildPath $($xConnect.CertificateName + ".crt") )
        SiteUtilitiesSrc                            = $(Join-Path -Path $assets.commerce.sifCommerceRoot -ChildPath "SiteUtilityPages")
        CommerceConnectModuleFullPath               = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce Connect*.zip" -Recurse  )
        CommercexProfilesModuleFullPath             = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce ExperienceProfile Core *.zip" -Recurse)
        CommercexAnalyticsModuleFullPath            = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce ExperienceAnalytics Core *.zip"	-Recurse)
        CommerceMAModuleFullPath                    = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce Marketing Automation Core *.zip"	-Recurse)
        CommerceMAForAutomationEngineModuleFullPath = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include "Sitecore Commerce Marketing Automation for AutomationEngine *.zip"	-Recurse)
        CEConnectModuleFullPath                     = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Engine Connect*.zip" -Recurse)
        SXACommerceModuleFullPath                   = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Experience Accelerator 2.*.zip" -Recurse)
        SXAStorefrontModuleFullPath                 = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Experience Accelerator Storefront 2.*.zip"-Recurse )
        SXAStorefrontThemeModuleFullPath            = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Experience Accelerator Storefront Themes*.zip"-Recurse )
        SXAStorefrontCatalogModuleFullPath          = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Sitecore Commerce Experience Accelerator Habitat Catalog*.zip" -Recurse)
        MergeToolFullPath                           = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "*Microsoft.Web.XmlTransform.dll" -Recurse | Select-Object -ExpandProperty FullName)
        HabitatImagesModuleFullPath                 = $(Get-ChildItem -Path $assets.commerce.installationFolder  -Include  "Habitat Home Product Images.zip" -Recurse)
        UserDomain                                  = $commerce.serviceAccountDomain
        UserName                                    = $commerce.serviceAccountUserName
        UserPassword                                = $commerce.serviceAccountPassword
        BraintreeAccount                            = @{
            MerchantId = $commerce.brainTreeAccountMerchandId
            PublicKey  = $commerce.brainTreeAccountPublicKey
            PrivateKey = $commerce.brainTreeAccountPrivateKey
        }
        SitecoreIdentityServerName                  = $commerce.identityServerName
    }
    write-host @params
    If (!$SkipHabitatHomeInstall) {
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs")
    }
    Else {
        Install-SitecoreConfiguration @params -Skip "InitializeCommerceEngine", "GenerateCatalogTemplates", "InstallHabitatImagesModule", "Reindex" -WorkingDirectory $(Join-Path $PWD "logs")
    }
}


#Install-Prerequisites
Install-RequiredInstallationAssets
Set-ModulesPath
Install-CommerceAssets
#Stop-XConnect - Should no longer do this as of 9.0.2
Publish-CommerceEngine
Publish-IdentityServer
Publish-BizFx
Install-Commerce
Start-Site
# Start-XConnect No longer required as of 9.0.2
