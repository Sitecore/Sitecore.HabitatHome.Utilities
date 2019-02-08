Param(
    [string] $ConfigurationFile = ".\configuration-xp0.json",
    [string] $LogFolder = ".\logs\",
    [string] $LogFileName = "install-habitathome.log",
    [string] $PathToHabitatHome
    
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
$config = Get-Content -Raw $ConfigurationFile |  ConvertFrom-Json
if (!$config) {
    throw "Error trying to load configuration!"
}  
$assets = $config.assets
$modules = $config.modules
$habitatHome = $config.modules | Where-Object {$_.id -like "habitathom*"}
$site = $config.settings.site
$sql = $config.settings.sql
$xConnect = $config.settings.xConnect
$resourcePath = Join-Path $assets.root "configuration"
$sharedResourcePath = Join-Path $assets.sharedUtilitiesPath "configuration"
$habitatHomeSettings = $config.settings.habitatHome
$downloadJsonPath = $([io.path]::combine($sharedResourcePath, 'download-assets.json'))
$downloadFolder = $assets.root
$packagesFolder = (Join-Path $downloadFolder "packages")

$credentials = $null

if (!(Test-Path $packagesFolder)) {
    New-Item $packagesFolder -ItemType Directory -Force  > $null  
}

Function Install-SitecoreInstallFramework {
    if ((Get-PSRepository | Where-Object {$_.Name -eq $assets.psRepositoryName}).count -eq 0) {
        Register-PSRepository -Name $assets.psRepositoryName -SourceLocation $assets.psRepository -InstallationPolicy Trusted 
    }

    #Sitecore Install Framework dependencies
    Import-Module WebAdministration
    
    #Install SIF
    $sifVersion = $assets.installerVersion
    
    $module = Get-Module -FullyQualifiedName @{ModuleName = "SitecoreInstallFramework"; ModuleVersion = $sifVersion }
    if (-not $module) {
        write-host "Installing the Sitecore Install Framework, version $($assets.installerVersion)" -ForegroundColor Green
        Install-Module SitecoreInstallFramework -Repository $assets.psRepositoryName -RequiredVersion $sifVersion -Scope CurrentUser -Force -AllowPrerelease
        Import-Module SitecoreInstallFramework -Force
    }
}

Function Install-SitecoreAzureToolkit {

    # Download Sitecore Azure Toolkit (used for converting modules)
    $package = $modules | Where-Object {$_.id -eq "sat"}

    Set-Alias sz 'C:\Program Files\7-Zip\7z.exe'
   
    $destination = $package.fileName
    
    if (!(Test-Path $destination) -and $package.install -eq $true) {
        if ($null -eq $credentials) {
            $credentials = Get-Credential -Message "Please provide dev.sitecore.com credentials"
        }
        $user = $credentials.GetNetworkCredential().UserName
        $password = $Credentials.GetNetworkCredential().Password

        $loginRequest = Invoke-RestMethod -Uri https://dev.sitecore.net/api/authorization -Method Post -ContentType "application/json" -Body "{username: '$user', password: '$password'}" -SessionVariable loginSession -UseBasicParsing 

        $params = @{
            Path         = $downloadJsonPath
            LoginSession = $loginSession
            Source       = $package.url
            Destination  = $destination
        }
        $Global:ProgressPreference = 'SilentlyContinue'
        Install-SitecoreConfiguration  @params  -Verbose 
        $Global:ProgressPreference = 'Continue'
    }
    if ((Test-Path $destination) -and ( $package.install -eq $true)) {
        sz x -o"$DownloadFolder\sat" $destination  -y -aoa
    }
    Import-Module (Join-Path $assets.root "SAT\tools\Sitecore.Cloud.CmdLets.dll") -Force 

}
Function Get-HabitatHome {

    $downloadAssets = $habitatHome
    if (!(Test-Path $downloadFolder)) {
        New-Item -ItemType Directory -Force -Path $downloadFolder
    }
    if (![string]::IsNullOrEmpty($PathToHabitatHome)) {
        # Path to Habitat Home assets provided. Use those instead of downloading
        Get-ChildItem $PathToHabitatHome -Recurse -Filter *.zip | Select-Object -ExpandProperty FullName | ForEach-Object { Copy-Item $_ $packagesFolder }
    }
    else {

        # Download modules
        $args = @{
            Packages         = $downloadAssets.modules
            PackagesFolder   = $packagesFolder
            DownloadJsonPath = $downloadJsonPath
        }
        Get-Packages @args
    }
}

Function Get-Packages {
    param(   [PSCustomObject] $Packages,
        $PackagesFolder,
        $Credentials,
        $DownloadJsonPath
    )
    foreach ($package in $Packages) {
        if (!(Test-Path $packagesFolder)) {
            New-Item -ItemType Directory -Force -Path $packagesFolder
        }
       
        if ($true -eq $package.install) {
            Write-Host ("Downloading {0}  -  if required" -f $package.name )
            $destination = $package.fileName
            if (!(Test-Path $destination)) {
        
                $user = ""# $credentials.GetNetworkCredential().UserName
                $password = ""# $Credentials.GetNetworkCredential().Password

                Invoke-RestMethod -Uri https://dev.sitecore.net/api/authorization -Method Post -ContentType "application/json" -Body "{username: '$user', password: '$password'}" -SessionVariable loginSession -UseBasicParsing 

                $params = @{
                    Path         = $downloadJsonPath
                    loginSession = $loginSession
                    Source       = $package.url
                    Destination  = $destination
                }
                $Global:ProgressPreference = 'SilentlyContinue'
                Install-SitecoreConfiguration  @params -WorkingDirectory $(Join-Path $PWD "logs")  
                $Global:ProgressPreference = 'Continue'
            }
        }
    }
}


Function Remove-DatabaseUsers {
    # Delete master and core database users

    Write-Host ("Removing {0}" -f $sql.coreUser) -ForegroundColor Green

    $params = @{
        Path             = (Join-Path $sharedResourcePath "remove-databaseuser.json")
        SqlServer        = $sql.server
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword
        DatabasePrefix   = $site.prefix
        DatabaseSuffix   = "Core"
        UserName         = $sql.coreUser
    }
    
    Install-SitecoreConfiguration @params  -WorkingDirectory $(Join-Path $PWD "logs")
   
    Write-Host ("Removing {0}" -f $sql.securityUser) -ForegroundColor Green

    $params = @{
        Path             = (Join-Path $sharedResourcePath "remove-databaseuser.json")
        SqlServer        = $sql.server
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword
        DatabasePrefix   = $site.prefix
        DatabaseSuffix   = "Core"
        UserName         = $sql.securityUser
    }
    
    Install-SitecoreConfiguration @params  -WorkingDirectory $(Join-Path $PWD "logs")
    
    Write-Host ("Removing {0}" -f $sql.masterUser) -ForegroundColor Green

    $params = @{
        Path             = (Join-Path $sharedResourcePath "remove-databaseuser.json")
        SqlServer        = $sql.server
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword
        DatabasePrefix   = $site.prefix
        DatabaseSuffix   = "Master"
        UserName         = $sql.masterUser
    }
    
    Install-SitecoreConfiguration @params  -WorkingDirectory $(Join-Path $PWD "logs")
}

Function Stop-Services {
    IISRESET /STOP
    Stop-Service "$($xConnect.siteName)-MarketingAutomationService"
    Stop-Service "$($xConnect.siteName)-IndexWorker"
    Stop-Service "$($xConnect.siteName)-ProcessingEngineService"
    $mssqlService = Get-Service *SQL* | Where-Object {$_.Status -eq 'Running' -and $_.DisplayName -like 'SQL Server (*'} | Select-Object -First 1 -ExpandProperty Name
    try {
        Write-Host "Restarting SQL Server"
        restart-service -force $mssqlService
    }
    catch {
        Write-Host "Something went wrong restarting SQL server again"
        restart-service -force $mssqlService
    }
}
Function Install-Bootloader {
    $bootLoaderPackagePath = [IO.Path]::Combine( $assets.root, "SAT\resources\9.1.0\Addons\Sitecore.Cloud.Integration.Bootload.wdp.zip")
    $bootloaderConfigurationOverride = $([io.path]::combine($sharedResourcePath, 'Sitecore.Cloud.Integration.Bootload.InstallJob.exe.config'))
    $bootloaderInstallationPath = $([io.path]::combine($site.webRoot, $site.hostName, "App_Data\tools\InstallJob"))
    
    $params = @{
        Path                             = (Join-path $sharedResourcePath 'bootloader.json')
        Package                          = $bootLoaderPackagePath
        SiteName                         = $site.hostName
        ConfigurationOverrideSource      = $bootloaderConfigurationOverride
        ConfigurationOverrideDestination = $bootloaderInstallationPath
    }
    
    Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs")

}

Function Install-HabitatHome {

    $hh = $habitatHome.modules | Where-Object { $_.id -eq "habitathome"} 
    if ($false -eq $hh.install) {
        return
    }
    
    $params = @{
        Path                              = (Join-path $resourcePath 'HabitatHome\habitathome.json')
        Package                           = $hh.fileName
        SiteName                          = $site.hostName
        SqlDbPrefix                       = $site.prefix 
        SqlAdminUser                      = $sql.adminUser 
        SqlAdminPassword                  = $sql.adminPassword 
        SqlServer                         = $sql.server
        DemoDynamicsCRMConnectionString   = ($habitatHomeSettings | Where-Object {$_.id -eq "DemoDynamicsCRMConnectionString"}).value
        DemoCRMSalesForceConnectionString = ($habitatHomeSettings | Where-Object {$_.id -eq "DemoCRMSalesForceConnectionString"}).value
        EnableEXMmodule                   = ($habitatHomeSettings | Where-Object {$_.id -eq "EnableEXMmodule"}).value
        AllowInvalidSSLCertificate        = ($habitatHomeSettings | Where-Object {$_.id -eq "AllowInvalidSSLCertificate"}).value
        EnvironmentType                   = ($habitatHomeSettings | Where-Object {$_.id -eq "EnvironmentType"}).value
        UnicornEnabled                    = ($habitatHomeSettings | Where-Object {$_.id -eq "UnicornEnabled"}).value
        ThirdPartyIntegrations            = ($habitatHomeSettings | Where-Object {$_.id -eq "ThirdPartyIntegrations"}).value
        ASPNETDebugging                   = ($habitatHomeSettings | Where-Object {$_.id -eq "ASPNETDebugging"}).value
        CDNEnabled                        = ($habitatHomeSettings | Where-Object {$_.id -eq "CDNEnabled"}).value
        MediaAlwaysIncludeServerURL       = ($habitatHomeSettings | Where-Object {$_.id -eq "MediaAlwaysIncludeServerURL"}).value
        MediaLinkServerURL                = ($habitatHomeSettings | Where-Object {$_.id -eq "MediaLinkServerURL"}).value
        MediaResponseCacheabilityType     = ($habitatHomeSettings | Where-Object {$_.id -eq "MediaResponseCacheabilityType"}).value
        DemoEnabled                       = ($habitatHomeSettings | Where-Object {$_.id -eq "DemoEnabled"}).value
        RootHostName                      = ($habitatHomeSettings | Where-Object {$_.id -eq "RootHostName"}).value
        AnalyticsCookieDomain             = ($habitatHomeSettings | Where-Object {$_.id -eq "AnalyticsCookieDomain"}).value
  
    }
    
    Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 
}
Function Install-HabitatHomeXConnect {

    $xc = $habitatHome.modules | Where-Object { $_.id -eq "habitathome_xConnect"}
    if ($false -eq $xc.install) {
        return
    }
     
    $params = @{
        Path             = (Join-path $sharedResourcePath 'module-mastercore.json')
        Package          = $xc.fileName
        SiteName         = $site.hostName
        SqlDbPrefix      = $site.prefix 
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword 
        SqlServer        = $sql.server 
    }
     
    Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 
   
   
}

Function Deploy-XConnectModels {
    $modelDestinations = @("App_Data\Models", "App_Data\jobs\continuous\IndexWorker\App_data\Models")
    $models = Get-ChildItem $([io.path]::combine($site.webRoot, $site.hostName, "App_Data\Models"))

    foreach ($model in $models) {

        foreach ($destination in $modelDestinations) {
            $deployModelParams = @{
                Path             = (Join-path $resourcePath 'xConnect\xconnect-models.json')
                WebRoot          = $site.webRoot
                SiteName         = $site.hostName
                XConnectSiteName = $xConnect.siteName
                ModelName        = $model.name
                Target           = $destination
            }
            Install-SitecoreConfiguration @deployModelParams -WorkingDirectory $(Join-Path $PWD "logs") 
        }
    }
}
Function Enable-ContainedDatabases {
    #Enable Contained Databases
    Write-Host "Enable contained databases" -ForegroundColor Green
    $params = @{
        Path             = (Join-Path $sharedResourcePath "enable-contained-databases.json")
        SqlServer        = $sql.server
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword
    }
    Install-SitecoreConfiguration @params  -WorkingDirectory $(Join-Path $PWD "logs")
}

Function Add-DatabaseUsers {
    Write-Host ("Adding {0}" -f $sql.coreUser) -ForegroundColor Green
    $sqlVariables = "DatabasePrefix = $($site.prefix)", "DatabaseSuffix = Core", "UserName = $($sql.coreUser)", "Password = $($sql.corePassword)"

    $params = @{
        Path             = (Join-Path $sharedResourcePath "execute-sql-script.json")
        SqlServer        = $sql.server
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword
        ScriptFile       = Join-Path $assets.sharedUtilitiesPath "\database\addcoredatabaseuser.sql"
        SqlVariables     = $sqlVariables
    }

    Install-SitecoreConfiguration @params  -WorkingDirectory $(Join-Path $PWD "logs")
  
    
    Write-Host ("Adding {0}" -f $sql.securityuser) -ForegroundColor Green
    $sqlVariables = "DatabasePrefix = $($site.prefix)", "DatabaseSuffix = Core", "UserName = $($sql.securityUser)", "Password = $($sql.securityPassword)"

    $params = @{
        Path             = (Join-Path $sharedResourcePath "execute-sql-script.json")
        SqlServer        = $sql.server
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword
        ScriptFile       = Join-Path $assets.sharedUtilitiesPath "\database\addcoredatabaseuser.sql" 
        SqlVariables     = $sqlVariables
    }
    
    Install-SitecoreConfiguration @params  -WorkingDirectory $(Join-Path $PWD "logs")
      
   
    Write-Host ("Adding {0}" -f $sql.masterUser) -ForegroundColor Green
    
    $sqlVariables = "DatabasePrefix = $($site.prefix)", "DatabaseSuffix = Master", "UserName = $($sql.masterUser)", "Password = $($sql.masterPassword)"
    $params = @{
        Path             = (Join-Path $sharedResourcePath "execute-sql-script.json")
        SqlServer        = $sql.server
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword
        ScriptFile       = Join-Path $assets.sharedUtilitiesPath "database\adddatabaseuser.sql" 
        SqlVariables     = $sqlVariables
    }
        
    Install-SitecoreConfiguration @params  -WorkingDirectory $(Join-Path $PWD "logs")
}

Function Start-Services {
    IISRESET /START
    Start-Service "$($xConnect.siteName)-MarketingAutomationService"
    Start-Service "$($xConnect.siteName)-IndexWorker"
    Start-Service "$($xConnect.siteName)-ProcessingEngineService"
   
}

Install-SitecoreInstallFramework
Install-SitecoreAzureToolkit
Get-HabitatHome
Remove-DatabaseUsers
Stop-Services
Install-Bootloader
Install-HabitatHome
Install-HabitatHomeXConnect
Deploy-XConnectModels
Enable-ContainedDatabases
Add-DatabaseUsers
Start-Services
$StopWatch.Stop()
$StopWatch