Param(
    [string] $ConfigurationFile = ".\configuration-xp0.json",
    [string] $LogFolder = ".\logs\",
    [string] $LogFileName = "install-modules.log",
    [string] $devSitecoreUsername,
    [securestring] $devSitecorePassword
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$StopWatch = New-Object -TypeName System.Diagnostics.Stopwatch
$StopWatch.Start()
#####################################################
#
#  Install Modules
#
#####################################################
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$LogFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogFolder)
if (!(Test-Path $LogFolder)) {
    New-item -ItemType Directory -Path $LogFolder
}
$LogFile = Join-path $LogFolder $LogFileName
if (Test-Path $LogFile) {
    Get-Item $LogFile | Remove-Item
}

if (!(Test-Path $ConfigurationFile)) {
    Write-Host "Configuration file '$($ConfigurationFile)' not found." -ForegroundColor Red
    Write-Host  "Please use 'set-installation...ps1' files to generate a configuration file." -ForegroundColor Red
    Exit 1
}
$config = Get-Content -Raw $ConfigurationFile | ConvertFrom-Json
if (!$config) {
    throw "Error trying to load configuration!"
}
$assets = $config.assets
$modules = $config.modules
$site = $config.settings.site
$sitecore = $config.settings.sitecore
$solr = $config.settings.solr
$sql = $config.settings.sql
$xConnect = $config.settings.xConnect
$sharedResourcePath = Join-Path $assets.sharedUtilitiesRoot "assets\configuration"
$downloadFolder = $assets.packageRepository
$packagesFolder = (Join-Path $downloadFolder "modules")

$loginSession = $null

Import-Module (Join-Path $assets.sharedUtilitiesRoot "assets\modules\SharedInstallationUtilities\SharedInstallationUtilities.psm1") -Force

Import-Module SqlServer

#Ensure the Correct SIF Version is Imported
Import-SitecoreInstallFramework -version $assets.installerVersion

if (!(Test-Path $packagesFolder)) {
    New-Item $packagesFolder -ItemType Directory -Force  > $null
}

Function Get-SitecoreCredentials {
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

Function Install-SitecoreAzureToolkit {
    # Download Sitecore Azure Toolkit (used for converting modules)
    $package = $modules | Where-Object { $_.id -eq "sat" }

    Set-Alias sz 'C:\Program Files\7-Zip\7z.exe'

    $destination = $package.fileName

    if (!(Test-Path $destination)) {
        Get-SitecoreCredentials

        $params = @{
            Path         = $([io.path]::combine($sharedResourcePath, 'download-assets.json'))
            LoginSession = $global:loginSession
            Source       = $package.url
            Destination  = $destination
        }
        $Global:ProgressPreference = 'SilentlyContinue'
        Install-SitecoreConfiguration  @params  -Verbose
        $Global:ProgressPreference = 'Continue'
    }
    if ((Test-Path $destination) -and ( $package.install -eq $true)) {
        sz x -o"$($assets.sitecoreazuretoolkit)" $destination  -y -aoa
    }
    Import-Module (Join-Path $assets.sitecoreazuretoolkit "tools\Sitecore.Cloud.CmdLets.dll") -Force
}

Function New-ModuleInstallationConfiguration {
    $installableModules = $modules | Where-Object { $_.install -eq $true -and $_.id -ne "sat" }
    $moduleConfigurationTemplate = Join-Path $sharedResourcePath  "templates\module-install-template.json"
    $moduleMasterInstallConfigurationTemplate = Join-Path $sharedResourcePath   "templates\module-master-install-template.json"

    $moduleMasterInstallationConfiguration = Join-Path $assets.root "configuration\module-installation\module-master-install.json"
    $moduleInstallationConfiguration = Join-Path $assets.root "configuration\module-installation\install-modules.json"

    $template = Get-Content $moduleConfigurationTemplate -Raw | ConvertFrom-Json
    $destination = Get-Content $moduleConfigurationTemplate -Raw | ConvertFrom-Json

    $masterConfiguration = Get-Content $moduleMasterInstallConfigurationTemplate -Raw | ConvertFrom-Json

    foreach ($installableModule in $installableModules) {
        $moduleParameters = New-Object PSObject
        $source = @{
            Source = Join-Path $sharedResourcePath "download-and-install-module.json"
        }
        $destination.Includes | Add-Member -Type NoteProperty -Name  $installableModule.id -Value $source

        $template.parameters | Get-ObjectMembers | ForEach-Object {
            $key = $_.Key
            $_.Value | Get-ObjectMembers | Foreach-Object {
                if ($_.Key -eq "Type") {
                    $value = @{
                        $_.key    = $_.value
                        Reference = $key
                    }
                    $moduleParameters | Add-Member -MemberType NoteProperty -Name ($installableModule.id + ':' + $key) -Value (ConvertTo-Json -InputObject $value | ConvertFrom-Json)
                }
            }
        }
        $moduleConfiguration = @{
            Type         = "psobject"
            DefaultValue = $installableModule
        }
        $moduleParameters | Add-Member -MemberType NoteProperty -Name ($installableModule.id + ':' + "ModuleConfiguration") -Value (ConvertTo-Json -InputObject $moduleConfiguration | ConvertFrom-Json)

        if ($null -ne $installablemodule.additionalInstallationSteps) {
            $additionalSteps = Get-Content $([io.path]::combine($sharedResourcePath, $installableModule.id, $installableModule.additionalInstallationSteps)) -Raw | ConvertFrom-Json

            $additionalSteps.Includes | Get-ObjectMembers | ForEach-Object { $masterConfiguration.Includes | Add-Member -MemberType NoteProperty -Name $_.Key -Value $_.Value -Force }
            $additionalSteps.Parameters | Get-ObjectMembers | Foreach-Object { $masterConfiguration.Parameters | Add-Member -MemberType NoteProperty -Name $_.Key -Value $_.Value -Force }
            if ($null -ne $additionalSteps.Variables) {
                $additionalSteps.Variables | Get-ObjectMembers | Foreach-Object { $masterConfiguration.Variables | Add-Member -MemberType NoteProperty -Name $_.Key -Value $_.Value -Force }
            }
        }
        $moduleParameters | Get-ObjectMembers | ForEach-Object { $destination.parameters | Add-Member -MemberType NoteProperty -Name $_.Key -Value $_.Value }
    }

    Set-Content $moduleMasterInstallationConfiguration  (ConvertTo-Json -InputObject $masterConfiguration -Depth 5) -Force

    Set-Content $moduleInstallationConfiguration  (ConvertTo-Json -InputObject $destination -Depth 5) -Force
}

Function Set-IncludesPath {
    $moduleMasterInstallationConfiguration = Join-Path $assets.root "configuration\module-installation\module-master-install.json"
    $moduleInstallationConfiguration = Join-Path $assets.root "configuration\module-installation\install-modules.json"
    [regex]$pattern = [regex]::escape(".\\")
    $pattern.replace((Get-Content $moduleMasterInstallationConfiguration -Raw), $sharedResourcePath.replace('\', '\\') + "\\") | Set-Content $moduleMasterInstallationConfiguration
    $pattern.replace((Get-Content $moduleInstallationConfiguration -Raw), $sharedResourcePath.replace('\', '\\') + "\\") | Set-Content $moduleInstallationConfiguration
    [regex]$pattern = "install-modules\.json"
    $pattern.replace((Get-Content $moduleMasterInstallationConfiguration -Raw), $moduleInstallationConfiguration.replace('\', '\\')) | Set-Content $moduleMasterInstallationConfiguration
}

Function Install-Modules {
    $bootLoaderPackagePath = [IO.Path]::Combine($assets.sitecoreazuretoolkit, "resources\9.2.0\Addons\Sitecore.Cloud.Integration.Bootload.wdp.zip")
    $bootloaderConfigurationOverride = $([io.path]::combine($assets.sharedUtilitiesRoot, "assets", 'Sitecore.Cloud.Integration.Bootload.InstallJob.exe.config'))
    $bootloaderInstallationPath = $([io.path]::combine($site.webRoot, $site.hostName, "App_Data\tools\InstallJob"))

    Get-SitecoreCredentials
    $params = @{
        Path                            = Join-Path $assets.root "configuration\module-installation\module-master-install.json"
        SiteName                        = $site.hostName
        WebRoot                         = $site.webRoot
        XConnectSiteName                = $xConnect.siteName
        SqlServer                       = $sql.server
        SqlAdminUser                    = $sql.adminUser
        SqlAdminPassword                = $sql.adminPassword
        DatabasePrefix                  = $site.prefix
        SecurityUserName                = $sql.securityUser
        SecurityUserPassword            = $sql.SecurityPassword
        CoreUserName                    = $sql.coreUser
        CoreUserPassword                = $sql.corePassword
        MasterUserName                  = $sql.masterUser
        MasterUserPassword              = $sql.MasterPassword
        BootLoaderPackagePath           = $bootLoaderPackagePath
        BootloaderConfigurationOverride = $bootloaderConfigurationOverride
        BootloaderInstallationPath      = $bootloaderInstallationPath
        LoginSession                    = $global:loginSession
        SolrUrl                         = $solr.url
        SolrRoot                        = $solr.root
        SolrService                     = $solr.serviceName
        CorePrefix                      = $site.prefix
        SitecoreAdminPassword           = $sitecore.adminPassword
    }
    Push-Location $sharedResourcePath
    Install-SitecoreConfiguration @params
    Pop-Location
}

Install-SitecoreAzureToolkit
New-ModuleInstallationConfiguration
Set-IncludesPath
Install-Modules

$StopWatch.Stop()
$StopWatch
