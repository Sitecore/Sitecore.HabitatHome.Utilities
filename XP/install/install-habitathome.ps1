Param(
    [string] $ConfigurationFile = ".\configuration-xp0.json",
    [string] $LogFolder = ".\logs\",
    [string] $LogFileName = "install-habitathome.log"
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

$downloadJsonPath = $([io.path]::combine($resourcePath, 'HabitatHome', 'download-assets.json'))
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
    
    if (!(Test-Path $destination) -and $package.download -eq $true) {
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
  
    # Download modules
    $args = @{
        Packages         = $downloadAssets
        PackagesFolder   = $packagesFolder
        DownloadJsonPath = $downloadJsonPath
    }
    Get-Packages @args
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
       
        if ($true -eq $package.download) {
            Write-Host ("Downloading {0}  -  if required" -f $package.name )
            $destination = $package.fileName
            if (!(Test-Path $destination)) {
                $user = ""# $credentials.GetNetworkCredential().UserName
                $password = ""# $Credentials.GetNetworkCredential().Password

                $loginRequest = Invoke-RestMethod -Uri https://dev.sitecore.net/api/authorization -Method Post -ContentType "application/json" -Body "{username: '$user', password: '$password'}" -SessionVariable loginSession -UseBasicParsing 

                $params = @{
                    Path        = $downloadJsonPath
                    loginSession = $loginSession
                    Source      = $package.url
                    Destination = $destination
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
    try {
        $sqlVariables = "DatabasePrefix = $($site.prefix)", "DatabaseSuffix = Core", "UserName = $($sql.coreUser)"
        Invoke-Sqlcmd -ServerInstance $sql.server `
            -Username $sql.adminUser `
            -Password $sql.adminPassword `
            -InputFile "$PSScriptRoot\database\removedatabaseuser.sql" `
            -Variable $sqlVariables
    }
    catch {
        write-host ("Removing Core user failed") -ForegroundColor Red
        throw
    }
    Write-Host ("Removing {0}" -f $sql.securityUser) -ForegroundColor Green
    try {
        $sqlVariables = "DatabasePrefix = $($site.prefix)", "DatabaseSuffix = Core", "UserName = $($sql.securityUser)"
        Invoke-Sqlcmd -ServerInstance $sql.server `
            -Username $sql.adminUser `
            -Password $sql.adminPassword `
            -InputFile "$PSScriptRoot\database\removedatabaseuser.sql" `
            -Variable $sqlVariables
    }
    catch {
        write-host ("Removing Core user failed") -ForegroundColor Red
        throw
    }
    Write-Host ("Removing {0}" -f $sql.masterUser) -ForegroundColor Green
    try {
        $sqlVariables = "DatabasePrefix = $($site.prefix)", "DatabaseSuffix = Master", "UserName = $($sql.masterUser)"
        Invoke-Sqlcmd -ServerInstance $sql.server `
            -Username $sql.adminUser `
            -Password $sql.adminPassword `
            -InputFile "$PSScriptRoot\database\removedatabaseuser.sql" `
            -Variable $sqlVariables
    }
    catch {
        write-host ("Removing Master user failed") -ForegroundColor Red        throw
    }
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
Function Install-Bootloader{
    $bootLoaderPackagePath = [IO.Path]::Combine( $assets.root, "SAT\resources\9.1.0\Addons\Sitecore.Cloud.Integration.Bootload.wdp.zip")
    $bootloaderConfigurationOverride = $([io.path]::combine($resourcePath, 'Sitecore.Cloud.Integration.Bootload.InstallJob.exe.config'))
    $bootloaderInstallationPath = $([io.path]::combine($site.webRoot,$site.hostName,"App_Data\tools\InstallJob"))
    
    $params = @{
        Path                                = (Join-path $resourcePath 'HabitatHome\bootloader.json')
        Package                             = $bootLoaderPackagePath
        SiteName                            = $site.hostName
        ConfigurationOverrideSource         = $bootloaderConfigurationOverride
        ConfigurationOverrideDestination    = $bootloaderInstallationPath
    }
    
    Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs")

}

Function Install-HabitatHome {

    $hh = $habitatHome | Where-Object { $_.id -eq "habitathome"}
    if ($false -eq $hh.install) {
        return
    }
    
    $params = @{
        Path             = (Join-path $resourcePath 'HabitatHome\habitathome.json')
        Package          = $hh.fileName
        SiteName         = $site.hostName
        SqlDbPrefix      = $site.prefix 
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword 
        SqlServer        = $sql.server 
    }
    
    Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 
}
Function Install-HabitatHomeXConnect {

    $xc = $habitatHome | Where-Object { $_.id -eq "habitathome_xConnect"}
    if ($false -eq $xc.install) {
        return
    }
     
    $params = @{
        Path             = (Join-path $resourcePath 'HabitatHome\module-mastercore.json')
        Package          = $xc.fileName
        SiteName         = $site.hostName
        SqlDbPrefix      = $site.prefix 
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword 
        SqlServer        = $sql.server 
    }
     
    Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 
}

Function Enable-ContainedDatabases {
    #Enable Contained Databases
    Write-Host "Enable contained databases" -ForegroundColor Green
    try {
        # This command can set the location to SQLSERVER:\
        Invoke-Sqlcmd -ServerInstance $sql.server `
            -Username $sql.adminUser `
            -Password $sql.adminPassword `
            -InputFile "$PSScriptRoot\database\containedauthentication.sql"
    }
    catch {
        write-host "Set Enable contained databases failed" -ForegroundColor Red
        throw
    }
}
Function Add-DatabaseUsers {
    Write-Host ("Adding {0}" -f $sql.coreUser) -ForegroundColor Green
    try {
        $sqlVariables = "DatabasePrefix = $($site.prefix)", "DatabaseSuffix = Core", "UserName = $($sql.coreUser)", "Password = $($sql.corePassword)"
        Invoke-Sqlcmd -ServerInstance $sql.server `
            -Username $sql.adminUser `
            -Password $sql.adminPassword `
            -InputFile "$PSScriptRoot\database\addcoredatabaseuser.sql" `
            -Variable $sqlVariables
    }
    catch {
        write-host "Set Collection User rights failed" -ForegroundColor Red
        throw
    }
    
    Write-Host ("Adding {0}" -f $sql.securityuser) -ForegroundColor Green
    try {
        $sqlVariables = "DatabasePrefix = $($site.prefix)", "DatabaseSuffix = Core", "UserName = $($sql.securityUser)", "Password = $($sql.securityPassword)"
        Invoke-Sqlcmd -ServerInstance $sql.server `
            -Username $sql.adminUser `
            -Password $sql.adminPassword `
            -InputFile "$PSScriptRoot\database\addcoredatabaseuser.sql" `
            -Variable $sqlVariables
    }
    catch {
        write-host "Set Collection User rights failed" -ForegroundColor Red
        throw
    }
    Write-Host ("Adding {0}" -f $sql.masterUser) -ForegroundColor Green
    try {
        $sqlVariables = "DatabasePrefix = $($site.prefix)", "DatabaseSuffix = Master", "UserName = $($sql.masterUser)", "Password = $($sql.masterPassword)"
        Invoke-Sqlcmd -ServerInstance $sql.server `
            -Username $sql.adminUser `
            -Password $sql.adminPassword `
            -InputFile "$PSScriptRoot\database\adddatabaseuser.sql" `
            -Variable $sqlVariables
    }
    catch {
        write-host "Set Collection User rights failed" -ForegroundColor Red
        throw
    }
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
Enable-ContainedDatabases
Add-DatabaseUsers
Start-Services
$StopWatch.Stop()
$StopWatch