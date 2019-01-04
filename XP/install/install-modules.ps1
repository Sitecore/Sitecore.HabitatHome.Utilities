Param(
    [string] $ConfigurationFile = ".\configuration-xp0.json",
    [string] $LogFolder = ".\logs\",
    [string] $LogFileName = "install-modules.log",
    [string] $devSitecoreUsername,
    [string] $devSitecorePassword
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
$site = $config.settings.site
$sitecore = $config.settings.sitecore
$solr = $config.settings.solr
$sql = $config.settings.sql
$xConnect = $config.settings.xConnect
$resourcePath = Join-Path $assets.root "configuration"

$downloadFolder = $assets.root
$packagesFolder = (Join-Path $downloadFolder "packages")


$loginSession = $null

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
    
    if (!(Test-Path $destination)) {
       
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
        

        $params = @{
            Path         = $([io.path]::combine($resourcePath, 'HabitatHome', 'download-assets.json'))
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

Function Install-SiteModule {
    param(
        $sitecoreModule
    )
    $baseConfigurationPath = Join-Path $resourcePath 'HabitatHome'
    $configuration = ("module-{0}.json" -f $sitecoreModule.databases.replace(",", ""))
    $configurationPath = Join-Path $baseConfigurationPath $configuration
    if ($true -eq $sitecoreModule.convert) {
        $sitecoreModule.filename = $sitecoreModule.filename.replace(".zip", ".scwdp.zip")
    }

    $params = @{
        Path             = $configurationPath
        Package          = $sitecoreModule.fileName
        SiteName         = $site.hostName
        SqlDbPrefix      = $site.prefix 
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword 
        SqlServer        = $sql.server 
    }
    
    Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 
}
Function Install-Modules {
    param(
        [PSCustomObject] $Packages,
        $Credentials
    )
    foreach ($package in $packages) {
        if ($package.isGroup -and  $true -eq $package.install) {
            $submodules = $package.modules
            $args = @{
                Packages    = $submodules
                Credentials = $Credentials
            }
            Install-Modules @args
        }
        elseif (!($package.PSObject.Properties.name -match "isGroup") -and $true -eq $package.install ) {
            Write-Host ("Downloading {0}  -  if required" -f $package.name )
            $destination = $package.fileName
            if (!(Test-Path $destination)) {
                if ($null -eq $credentials) {
                    if ([string]::IsNullOrEmpty($devSitecoreUsername)) {
                        $credentials = Get-Credential -Message "Please provide dev.sitecore.com credentials"
                    }
                    elseif (![string]::IsNullOrEmpty($devSitecoreUsername) -and ![string]::IsNullOrEmpty($devSitecorePassword)) {
                        $secpasswd = ConvertTo-SecureString $devSitecorePassword -AsPlainText -Force
                        $Credentials = New-Object System.Management.Automation.PSCredential ($devSitecoreUsername, $secpasswd)
                    }
                    else {
                        throw "Credentials required for download"
                    }
                }
                $user = $credentials.GetNetworkCredential().UserName
                $password = $credentials.GetNetworkCredential().Password

                Invoke-RestMethod -Uri https://dev.sitecore.net/api/authorization -Method Post -ContentType "application/json" -Body "{username: '$user', password: '$password'}" -SessionVariable loginSession -UseBasicParsing 
                $params = @{
                    Path         = $([io.path]::combine($resourcePath, 'HabitatHome', 'download-assets.json'))
                    LoginSession = $loginSession
                    Source       = $package.url
                    Destination  = $destination
                }
                $Global:ProgressPreference = 'SilentlyContinue'
                Install-SitecoreConfiguration  @params -WorkingDirectory $(Join-Path $PWD "logs")  
                $Global:ProgressPreference = 'Continue'
            }
            
            if ($package.convert) {
                Write-Host ("Converting {0} to SCWDP" -f $package.name) -ForegroundColor Green
                ConvertTo-SCModuleWebDeployPackage  -Path $destination -Destination $PackagesFolder -Force
            }
            Install-SitecoreModule $package
        }
    }
}
Function Start-ModuleInstallation {
    $excluded = @("xp", "sat", "si", "habitatHome")
    $installableModules = $modules | Where-Object { $_.id -notin $excluded }  #  if ($package.id -eq "xp" -or $package.id -eq "sat" -or $package.id -eq "si" -or $package.id -eq "habitatHome") {
   
    if (!(Test-Path $downloadFolder)) {
        New-Item -ItemType Directory -Force -Path $downloadFolder
    }
      
    # Download modules
    $args = @{
        Packages    = $installableModules
        Credentials = $global:credentials
    }
    Install-Modules @args
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
function Update-SXASolrCores {
    try {
        $sxa = $modules | Where-Object { $_.id -eq "sxa"}
        if ($false -eq $sxa.install) {
            return
        }
        $params = @{
            Path        = Join-Path $resourcePath "HabitatHome\configure-search-indexes.json"
            InstallDir  = Join-Path $site.webRoot $site.hostName
            ResourceDir = $($assets.root + "\\configuration")
            SitePrefix  = $site.prefix
        }
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs")
    }
    catch {
        write-host "$site.hostName Failed to updated search index configuration" -ForegroundColor Red
        throw
    }
    # Install SXA Solr Cores
    
    $sxaSolrConfigPath = Join-Path $resourcePath 'HabitatHome\sxa-solr-config.json'
    
    try {
        $params = @{
            Path                  = Join-path $resourcePath 'HabitatHome\sxa-solr.json'
            SolrUrl               = $solr.url 
            SolrRoot              = $solr.root 
            SolrService           = $solr.serviceName 
            CorePrefix            = $site.prefix
            SXASolrConfigPath     = $sxaSolrConfigPath
            SiteName              = $site.hostName
            SitecoreAdminPassword = $sitecore.adminPassword
 
        }
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs")
    }
    catch {
        write-host "SXA SOLR Failed" -ForegroundColor Red
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
Remove-DatabaseUsers
Stop-Services
Start-ModuleInstallation
Enable-ContainedDatabases
Add-DatabaseUsers
Start-Services
Update-SXASolrCores
$StopWatch.Stop()
$StopWatch