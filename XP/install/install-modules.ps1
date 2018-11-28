Param(
    [string] $ConfigurationFile = ".\configuration-xp0.json",
    [string] $LogFolder = ".\logs\",
    [string] $LogFileName = "install-modules.log"
)


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

$downloadJsonPath = $([io.path]::combine($resourcePath, 'HabitatHome', 'download-assets.json'))
$downloadFolder = $assets.root
$packagesFolder = (Join-Path $downloadFolder "packages")

$credentials = $null
$loginSession = $null
Function Install-SitecoreInstallFramework {
    if ((Get-PSRepository | Where-Object {$_.Name -eq $assets.psRepositoryName}).count -eq 0) {
        Register-PSRepository -Name $assets.psRepositoryName -SourceLocation $assets.psRepository -InstallationPolicy Trusted 
    }

    #Sitecore Install Framework dependencies
    Import-Module WebAdministration
    
    #Install SIF
    $sifVersion = $assets.installerVersion -replace "-beta[0-9]*$"
    
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
Function Get-OptionalModules {

    $downloadAssets = $modules
    if (!(Test-Path $downloadFolder)) {
        New-Item -ItemType Directory -Force -Path $downloadFolder
    }
  
    # Download modules
    $args = @{
        Packages         = $downloadAssets
        PackagesFolder   = $packagesFolder
        Credentials      = $credentials
        DownloadJsonPath = $downloadJsonPath
    }
    Process-Packages @args
}

Function Process-Packages {
    param(   [PSCustomObject] $Packages,
        $PackagesFolder,
        $Credentials,
        $DownloadJsonPath
    )
    foreach ($package in $Packages) {
        if ($package.id -eq "xp" -or $package.id -eq "sat" -or $package.id -eq "si") {
            # Skip Sitecore Azure Toolkit and XP package and Sitecore identity - previously downloaded
            continue;
        }

        if (!(Test-Path $packagesFolder)) {
            New-Item -ItemType Directory -Force -Path $packagesFolder
        }
       
        if ($package.isGroup) {
            $submodules = $package.modules
            $args = @{
                Packages         = $submodules
                PackagesFolder   = $PackagesFolder
                Credentials      = $Credentials
                DownloadJsonPath = $DownloadJsonPath
            }
            Process-Packages @args
        }
        elseif ($true -eq $package.download -and (!($package.PSObject.Properties.name -match "isGroup") ) ) {
            Write-Host ("Downloading {0}  -  if required" -f $package.name )
            $destination = $package.fileName
            if (!(Test-Path $destination)) {
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
                Install-SitecoreConfiguration  @params -WorkingDirectory $(Join-Path $PWD "logs")  
                $Global:ProgressPreference = 'Continue'
            }
            Write-Host $package
            if ($package.convert) {
                Write-Host ("Converting {0} to SCWDP" -f $package.name) -ForegroundColor Green
                ConvertTo-SCModuleWebDeployPackage  -Path $destination -Destination $PackagesFolder -Force
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
Function Install-SitecorePowerShellExtensions {
   
    $spe = $modules | Where-Object { $_.id -eq "spe"}
    if ($false -eq $spe.install) {
        return
    }
    #$spe.fileName = $spe.fileName.replace(".zip", ".scwdp.zip")
    $params = @{
        Path             = (Join-path $resourcePath 'HabitatHome\module-mastercore.json')
        Package          = $spe.fileName
        SiteName         = $site.hostName
        SqlDbPrefix      = $site.prefix 
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword 
        SqlServer        = $sql.server 

    }
    
    Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 
}

Function Install-SitecoreExperienceAccelerator {

    # Install SXA

    $sxa = $modules | Where-Object { $_.id -eq "sxa"}
    if ($false -eq $sxa.install) {
        return
    }
    # $sxa.fileName = $sxa.fileName.replace(".zip", ".scwdp.zip")
    $params = @{
        Path             = (Join-path $resourcePath 'HabitatHome\module-mastercore.json')
        Package          = $sxa.fileName
        SiteName         = $site.hostName
        SqlDbPrefix      = $site.prefix 
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword 
        SqlServer        = $sql.server 

    }
    
    Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 
}

Function Install-DataExchangeFrameworkModules {
    $defGroup = $modules | Where-Object { $_.id -eq "defGroup"}
    $defModules = ($modules | Where-Object { $_.id -eq "defGroup"}).modules

    if ($true -eq $defGroup.install) {
        $def = $defModules | Where-Object { $_.id -eq "def"}
        Write-Host ("Installing {0}" -f $def.name)
        $def.fileName = $def.fileName.replace(".zip", ".scwdp.zip")
        $params = @{
            Path             = (Join-path $resourcePath 'HabitatHome\module-mastercore.json')
            Package          = $def.fileName
            SiteName         = $site.hostName
            SqlDbPrefix      = $site.prefix 
            SqlAdminUser     = $sql.adminUser 
            SqlAdminPassword = $sql.adminPassword 
            SqlServer        = $sql.server 

        }
    
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 

        $defSitecore = $defModules | Where-Object { $_.id -eq "defSitecore"}
        Write-Host ("Installing {0}" -f $defSitecore.name)
        $defSitecore.fileName = $defSitecore.fileName.replace(".zip", ".scwdp.zip")
        $params = @{
            Path             = (Join-path $resourcePath 'HabitatHome\module-master.json')
            Package          = $defSitecore.fileName
            SiteName         = $site.hostName
            SqlDbPrefix      = $site.prefix 
            SqlAdminUser     = $sql.adminUser 
            SqlAdminPassword = $sql.adminPassword 
            SqlServer        = $sql.server 

        }
    
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 

        $defSql = $defModules | Where-Object { $_.id -eq "defSql"}
        Write-Host ("Installing {0}" -f $defSql.name)
        $defSql.fileName = $defSql.fileName.replace(".zip", ".scwdp.zip")
        $params = @{
            Path             = (Join-path $resourcePath 'HabitatHome\module-master.json')
            Package          = $defSql.fileName
            SiteName         = $site.hostName
            SqlDbPrefix      = $site.prefix 
            SqlAdminUser     = $sql.adminUser 
            SqlAdminPassword = $sql.adminPassword 
            SqlServer        = $sql.server 

        }
    
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 

        $defxConnect = $defModules | Where-Object { $_.id -eq "defxConnect"}
        Write-Host ("Installing {0}" -f $defxConnect.name)
        $defxConnect.fileName = $defxConnect.fileName.replace(".zip", ".scwdp.zip")
        $params = @{
            Path             = (Join-path $resourcePath 'HabitatHome\module-mastercore.json')
            Package          = $defxConnect.fileName
            SiteName         = $site.hostName
            SqlDbPrefix      = $site.prefix 
            SqlAdminUser     = $sql.adminUser 
            SqlAdminPassword = $sql.adminPassword 
            SqlServer        = $sql.server 

        }
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 
    }
    ### Dynamics
    
    $defDynamicsGroup = $defModules | Where-Object {$_.id -eq "defDynamicsGroup"}
    
    if ($true -eq $defDynamicsGroup.install) {
        $defDynamics = $defDynamicsGroup.modules | Where-Object { $_.id -eq "defDynamics"}
        Write-Host ("Installing {0}" -f $defDynamics.name)
        $defDynamics.fileName = $defDynamics.fileName.replace(".zip", ".scwdp.zip")
        $params = @{
            Path             = (Join-path $resourcePath 'HabitatHome\module-master.json')
            Package          = $defDynamics.fileName
            SiteName         = $site.hostName
            SqlDbPrefix      = $site.prefix 
            SqlAdminUser     = $sql.adminUser 
            SqlAdminPassword = $sql.adminPassword 
            SqlServer        = $sql.server 

        }
    
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 
    
        $defDynamicsConnect = $defDynamicsGroup.modules | Where-Object { $_.id -eq "defDynamicsConnect"}
        Write-Host ("Installing {0}" -f $defDynamicsConnect.name)
        $defDynamicsConnect.fileName = $defDynamicsConnect.fileName.replace(".zip", ".scwdp.zip")
        $params = @{
            Path             = (Join-path $resourcePath 'HabitatHome\module-master.json')
            Package          = $defDynamicsConnect.fileName
            SiteName         = $site.hostName
            SqlDbPrefix      = $site.prefix 
            SqlAdminUser     = $sql.adminUser 
            SqlAdminPassword = $sql.adminPassword 
            SqlServer        = $sql.server 

        }
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 
    }

    ### Salesforce

    $defSalesforceGroup = $defModules | Where-Object {$_.id -eq "defSalesforceGroup"}
    
    if ($true -eq $defSalesforceGroup.install) {

        $defSalesforce = $defSalesforceGroup.modules | Where-Object { $_.id -eq "defSalesforce"}
        Write-Host ("Installing {0}" -f $defSalesforce.name)
        $defSalesforce.fileName = $defSalesforce.fileName.replace(".zip", ".scwdp.zip")
        $params = @{
            Path             = (Join-path $resourcePath 'HabitatHome\module-master.json')
            Package          = $defSalesforce.fileName
            SiteName         = $site.hostName
            SqlDbPrefix      = $site.prefix 
            SqlAdminUser     = $sql.adminUser 
            SqlAdminPassword = $sql.adminPassword 
            SqlServer        = $sql.server 

        }
    
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 
    
        $defSalesforceConnect = $defSalesforceGroup.modules | Where-Object { $_.id -eq "defSalesforceConnect"}
        Write-Host ("Installing {0}" -f $defSalesforceConnect.name)
        $defSalesforceConnect.fileName = $defSalesforceConnect.fileName.replace(".zip", ".scwdp.zip")
        $params = @{
            Path             = (Join-path $resourcePath 'HabitatHome\module-master.json')
            Package          = $defSalesforceConnect.fileName
            SiteName         = $site.hostName
            SqlDbPrefix      = $site.prefix 
            SqlAdminUser     = $sql.adminUser 
            SqlAdminPassword = $sql.adminPassword 
            SqlServer        = $sql.server 

        }
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 
    }
}

Function Install-SalesforceMarketingCloudModule {
    $sfmcConnect = $modules | Where-Object { $_.id -eq "sfmcConnect"}
    if ($false -eq $sfmcConnect.install) {
        return;
    }

    $sfmcConnect.fileName = $sfmcConnect.fileName.replace(".zip", ".scwdp.zip")
    $params = @{
        Path             = (Join-path $resourcePath 'HabitatHome\module-mastercore.json')
        Package          = $sfmcConnect.fileName
        SiteName         = $site.hostName
        SqlDbPrefix      = $site.prefix 
        SqlAdminUser     = $sql.adminUser 
        SqlAdminPassword = $sql.adminPassword 
        SqlServer        = $sql.server 

    }
    
    Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") 
}
Function Install-StacklaModule {
    $stackla = $modules | Where-Object { $_.id -eq "stackla"}
    if ($false -eq $stackla.install) {
        return;
    }

    $stackla.fileName = $stackla.fileName.replace(".zip", ".scwdp.zip")
    $params = @{
        Path             = (Join-path $resourcePath 'HabitatHome\module-mastercore.json')
        Package          = $stackla.fileName
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
function Update-SXASolrCores {
    try {
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
Get-OptionalModules
Remove-DatabaseUsers
Stop-Services
Install-SitecorePowerShellExtensions
Install-SitecoreExperienceAccelerator
Install-DataExchangeFrameworkModules
Install-SalesforceMarketingCloudModule
Install-StacklaModule
Enable-ContainedDatabases
Add-DatabaseUsers
Start-Services
Update-SXASolrCores
$StopWatch.Stop()
$StopWatch