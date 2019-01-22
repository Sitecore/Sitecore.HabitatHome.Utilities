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
$sharedResourcePath = Join-Path $assets.sharedUtilitiesRoot "assets\configuration"
$downloadFolder = $assets.root
$packagesFolder = (Join-Path $downloadFolder "packages")


    Write-Host "Setting Modules Path" -ForegroundColor Green
    $modulesPath = ( Join-Path -Path $assets.sharedUtilitiesRoot -ChildPath "assets\Modules" )
    if ($env:PSModulePath -notlike "*$modulesPath*") {
        $p = $env:PSModulePath + ";" + $modulesPath
        [Environment]::SetEnvironmentVariable("PSModulePath", $p)
    }


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
            Path         = $([io.path]::combine($sharedResourcePath, 'download-assets.json'))
            LoginSession = $loginSession
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

Function Install-Modules {

    $bootLoaderPackagePath = [IO.Path]::Combine( $assets.sitecoreazuretoolkit, "resources\9.1.0\Addons\Sitecore.Cloud.Integration.Bootload.wdp.zip")
    $bootloaderConfigurationOverride = $([io.path]::combine($sharedResourcePath, 'Sitecore.Cloud.Integration.Bootload.InstallJob.exe.config'))
    $bootloaderInstallationPath = $([io.path]::combine($site.webRoot, $site.hostName, "App_Data\tools\InstallJob"))
    $assetsJson = (Resolve-Path $ConfigurationFile) # (Resolve-Path ".\assets.json")

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

    $params = @{
        Path                            = (Join-Path $sharedResourcePath "module-master-install.json")
        SiteName                        = $site.hostName
        XCOnnectSiteName                = $xConnect.siteName
        BootLoaderPackagePath           = $bootLoaderPackagePath
        BootloaderConfigurationOverride = $bootloaderConfigurationOverride
        BootloaderInstallationPath      = $bootloaderInstallationPath
        SqlServer                       = $sql.server
        SqlAdminUser                    = $sql.adminUser 
        SqlAdminPassword                = $sql.adminPassword
        DatabasePrefix                  = $site.prefix
        SecurityUserName                = $sql.securityUser
        CoreUserName                    = $sql.coreUser
        MasterUserName                  = $sql.masterUser
        AssetsJson                      = $assetsJson
        LoginSession                    = $loginSession
    }
    Push-Location $sharedResourcePath
    Install-SitecoreConfiguration @params -Verbose  
    Pop-Location
   
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
        ScriptFile       = Join-Path $assets.sharedUtilitiesRoot "\database\addcoredatabaseuser.sql"
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
        ScriptFile       = Join-Path $assets.sharedUtilitiesRoot "\database\addcoredatabaseuser.sql" 
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
        ScriptFile       = Join-Path $assets.sharedUtilitiesRoot "database\adddatabaseuser.sql" 
        SqlVariables     = $sqlVariables
    }
        
    Install-SitecoreConfiguration @params  -WorkingDirectory $(Join-Path $PWD "logs")
      
}
function Update-SXASolrCores {
    try {
        $sxa = $modules | Where-Object { $_.id -eq "sxa"}
        if ($false -eq $sxa.install) {
            return
        }
        $params = @{
            Path        = Join-Path $resourcePath "SXA\configure-search-indexes.json"
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
    
    $sxaSolrConfigPath = Join-Path $resourcePath 'SXA\sxa-solr-config.json'
    
    try {
        $params = @{
            Path                  = Join-path $resourcePath 'SXA\sxa-solr.json'
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
Install-Modules
Add-DatabaseUsers
Start-Services
Update-SXASolrCores
$StopWatch.Stop()
$StopWatch
