Param(
    [string] $ConfigurationFile = "configuration-xp0.json",
    [string] $LogFolder = ".\logs\",
    [string] $LogFileName = "install-sitecore.log",
    [string] $devSitecoreUsername,
    [string] $devSitecorePassword
)

#####################################################
# 
#  Install Sitecore
# 
#####################################################
$ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$StopWatch = New-Object -TypeName System.Diagnostics.Stopwatch 
$StopWatch.Start()


Set-Location $PSScriptRoot
$LogFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogFolder) 
if (!(Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder
}
$LogFile = Join-Path $LogFolder $LogFileName
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

$site = $config.settings.site
$sql = $config.settings.sql
$xConnect = $config.settings.xConnect
$sitecore = $config.settings.sitecore
$identityServer = $config.settings.identityServer
$solr = $config.settings.solr
$assets = $config.assets
$modules = $config.modules
$resourcePath = Join-Path $assets.root "configuration"
$sharedResourcePath = Join-Path $assets.sharedUtilitiesRoot "assets\configuration"

Write-Host "*******************************************************" -ForegroundColor Green
Write-Host " Installing Sitecore" -ForegroundColor Green
Write-Host " Sitecore: $($site.hostName)" -ForegroundColor Green
Write-Host " xConnect: $($xConnect.siteName)" -ForegroundColor Green
Write-Host " identityserver: $($identityServer.name)" -ForegroundColor Green
Write-Host "*******************************************************" -ForegroundColor Green

Function Install-SitecoreInstallFramework {
    #Register Assets PowerShell Repository
    if ((Get-PSRepository | Where-Object { $_.Name -eq $assets.psRepositoryName }).count -eq 0) {
        Register-PSRepository -Name $assets.psRepositoryName -SourceLocation $assets.psRepository -InstallationPolicy Trusted 
    }

    #Sitecore Install Framework dependencies
    Import-Module WebAdministration
    
    #Install SIF
    $sifVersion = $assets.installerVersion -replace "-beta[0-9]*$"
    
    $module = Get-Module -FullyQualifiedName @{ModuleName = "SitecoreInstallFramework"; ModuleVersion = $sifVersion }
    if (-not $module) {
        Write-Host "Installing the Sitecore Install Framework, version $($assets.installerVersion)" -ForegroundColor Green
        Install-Module SitecoreInstallFramework -Repository $assets.psRepositoryName -Scope CurrentUser -Force
        Import-Module SitecoreInstallFramework -Force
    }
}
Function Download-Assets {

    $downloadAssets = $modules
    $downloadFolder = $assets.root
    $packagesFolder = (Join-Path $downloadFolder "packages")
    
   
    # Download Sitecore
    if (!(Test-Path $downloadFolder)) {
        New-Item -ItemType Directory -Force -Path $downloadFolder
    }
    if ($null -eq $credentials) {
        if ([string]::IsNullOrEmpty($devSitecoreUsername)) {
            $credentials = Get-Credential -Message "Please provide dev.sitecore.com credentials"
        }
        elseif (![string]::IsNullOrEmpty($devSitecoreUsername) -and ![string]::IsNullOrEmpty($devSitecorePassword)) {
            $secpasswd = ConvertTo-SecureString $devSitecorePassword -AsPlainText -Force
            $credentials = New-Object System.Management.Automation.PSCredential ($devSitecoreUsername, $secpasswd)
        }
        else {
            throw "Credentials required for download"
        }
    }
    $user = $credentials.GetNetworkCredential().UserName
    $password = $Credentials.GetNetworkCredential().Password

    $loginRequest = Invoke-RestMethod -Uri https://dev.sitecore.net/api/authorization -Method Post -ContentType "application/json" -Body "{username: '$user', password: '$password'}" -SessionVariable loginSession -UseBasicParsing 

    $downloadJsonPath = $([io.path]::combine($sharedResourcePath, 'download-assets.json'))
    Set-Alias sz 'C:\Program Files\7-Zip\7z.exe'
    $package = $modules | Where-Object { $_.id -eq "xp" }
    
    Write-Host ("Downloading {0}  -  if required" -f $package.name )
        
    $destination = $package.fileName
            
    if (!(Test-Path $destination)) {
        $params = @{
            Path         = $downloadJsonPath
            LoginSession = $loginSession
            Source       = $package.url
            Destination  = $destination
        }
        $Global:ProgressPreference = 'SilentlyContinue'
        Install-SitecoreConfiguration  @params  *>&1 | Tee-Object $LogFile -Append 
        $Global:ProgressPreference = 'Continue'
    }
    if ((Test-Path $destination) -and ( $package.extract -eq $true)) {
        sz x -o"$DownloadFolder" $destination  -y -aoa
    }
    
}
Function Confirm-Prerequisites {
    #Enable Contained Databases
    Write-Host "Enable contained databases" -ForegroundColor Green
   
    Function Enable-ContainedDatabases {
        #Enable Contained Databases
        Write-Host "Enable contained databases" -ForegroundColor Green
        $params = @{
            Path             = (Join-Path $$sharedResourcePath "enable-contained-databases.json")
            SqlServer        = $sql.server
            SqlAdminUser     = $sql.adminUser 
            SqlAdminPassword = $sql.adminPassword
        }
        Install-SitecoreConfiguration @params -Verbose -WorkingDirectory $(Join-Path $PWD "logs")
    }

    # Reset location to script root
    Set-Location $PSScriptRoot

    # Verify Solr
    Write-Host "Verifying Solr connection" -ForegroundColor Green
    if (-not $solr.url.ToLower().StartsWith("https")) {
        throw "Solr URL ($SolrUrl) must be secured with https"
    }
    Write-Host "Solr URL: $($solr.url)"
    $SolrRequest = [System.Net.WebRequest]::Create($solr.url)
    $SolrResponse = $SolrRequest.GetResponse()
    try {
        If ($SolrResponse.StatusCode -ne 200) {
            Write-Host "Could not contact Solr on '$($solr.url)'. Response status was '$SolrResponse.StatusCode'" -ForegroundColor Red
            
        }
    }
    finally {
        $SolrResponse.Close()
    }
    
    Write-Host "Verifying Solr directory" -ForegroundColor Green
    if (-not (Test-Path "$($solr.root)\server")) {
        throw "The Solr root path '$($solr.root)' appears invalid. A 'server' folder should be present in this path to be a valid Solr distributive."
    }

    Write-Host "Verifying Solr service" -ForegroundColor Green
    try {
        $null = Get-Service $solr.serviceName
    }
    catch {
        throw "The Solr service '$($solr.serviceName)' does not exist. Perhaps it's incorrect in settings.ps1?"
    }

    #Verify that assets are present
    if (!(Test-Path $assets.root)) {
        throw "$($assets.root) not found"
    }

    #Verify license file
    if (!(Test-Path $assets.licenseFilePath)) {
        throw "License file $($assets.licenseFilePath) not found"
    }
    
    #Verify Sitecore package
    if (!(Test-Path $sitecore.packagePath)) {
        throw "Sitecore package $($sitecore.packagePath) not found"
    }
    
    #Verify xConnect package
    if (!(Test-Path $xConnect.packagePath)) {
        throw "XConnect package $($xConnect.packagePath) not found"
    }
}

Function Install-SingleDeveloper {

    $singleDeveloperParams = @{
        Path                           = $sitecore.singleDeveloperConfigurationPath
        CertificatePath                = $assets.certificatesPath
        SqlServer                      = $sql.server
        SqlAdminUser                   = $sql.adminUser
        SqlAdminPassword               = $sql.adminPassword
        SqlCollectionPassword          = $sql.collectionPassword
        SqlReferenceDataPassword       = $sql.referenceDataPassword
        SqlMarketingAutomationPassword = $sql.marketingAutomationPassword
        SqlMessagingPassword           = $sql.messagingPassword
        SqlProcessingEnginePassword    = $sql.processingEnginePassword
        SqlReportingPassword           = $sql.reportingPassword
        SqlCorePassword                = $sql.corePassword
        SqlSecurityPassword            = $sql.securityPassword
        SqlMasterPassword              = $sql.masterPassword
        SqlWebPassword                 = $sql.webPassword
        SqlProcessingTasksPassword     = $sql.processingTasksPassword
        SqlFormsPassword               = $sql.formsPassword
        SqlExmMasterPassword           = $sql.exmMasterPassword
        SitecoreAdminPassword          = $sitecore.adminPassword
        SolrUrl                        = $solr.url
        SolrRoot                       = $solr.root
        SolrService                    = $solr.serviceName
        Prefix                         = $site.prefix
        XConnectCertificateName        = $xconnect.siteName
        XConnectCertificatePassword    = $sql.adminPassword
        IdentityServerCertificateName  = $identityServer.name
        IdentityServerSiteName         = $identityServer.name
        LicenseFile                    = $assets.licenseFilePath
        XConnectPackage                = $xConnect.packagePath
        SitecorePackage                = $sitecore.packagePath
        IdentityServerPackage          = $identityServer.packagePath
        XConnectSiteName               = $xConnect.siteName
        SitecoreSitename               = $site.hostName
        PasswordRecoveryUrl            = "https://" + $site.hostName
        SitecoreIdentityAuthority      = "https://" + $identityServer.name
        XConnectCollectionService      = "https://" + $xConnect.siteName
        ClientSecret                   = $identityServer.clientSecret
        AllowedCorsOrigins             = ("https://{0}|https://{1}" -f $site.hostName, "habitathomebasic.dev.local") # Need to add to proper config
        WebRoot                        = $site.webRoot
    }

    Push-Location (Join-Path $resourcePath "XP0")
    Install-SitecoreConfiguration @singleDeveloperParams 
    Pop-Location
}
Function Add-AppPoolMembership {

    #Add ApplicationPoolIdentity to performance log users to avoid Sitecore log errors (https://kb.sitecore.net/articles/404548)
    
    try {
        Add-LocalGroupMember "Performance Log Users" "IIS AppPool\$($site.hostName)"
        Write-Host "Added IIS AppPool\$($site.hostName) to Performance Log Users" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Couldn't add IIS AppPool\$($site.hostName) to Performance Log Users -- user may already exist" -ForegroundColor Yellow
    }
    try {
        Add-LocalGroupMember "Performance Monitor Users" "IIS AppPool\$($site.hostName)"
        Write-Host "Added IIS AppPool\$($site.hostName) to Performance Monitor Users" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Couldn't add IIS AppPool\$($site.hostName) to Performance Monitor Users -- user may already exist" -ForegroundColor Yellow
    }
    try {
        Add-LocalGroupMember "Performance Monitor Users" "IIS AppPool\$($xConnect.siteName)"
        Write-Host "Added IIS AppPool\$($xConnect.siteName) to Performance Monitor Users" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Couldn't add IIS AppPool\$($site.hostName) to Performance Monitor Users -- user may already exist" -ForegroundColor Yellow
    }
    try {
        Add-LocalGroupMember "Performance Log Users" "IIS AppPool\$($xConnect.siteName)"
        Write-Host "Added IIS AppPool\$($xConnect.siteName) to Performance Log Users" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Couldn't add IIS AppPool\$($xConnect.siteName) to Performance Log Users -- user may already exist" -ForegroundColor Yellow
    }
}

Function Add-AdditionalBindings {
    foreach ($binding in $site.additionalBindings) {
        $params = @{
            Path            = $site.addSiteBindingWithSSLPath 
            SiteName        = $site.hostName 
            WebRoot         = $site.webRoot 
            HostHeader      = $binding.hostName 
            Port            = $binding.port
            CertPath        = $assets.certificatesPath
            CertificateName = $binding.hostName
            Skip            = @()
        }
        if ($false -eq $binding.createCertificate) {
            $params.Skip += "CreatePaths", "CreateRootCert", "ImportRootCertificate", "CreateSignedCert"
        }
        if ($binding.sslOnly) {
            $params.Skip += "CreateBindings"
        }

        Install-SitecoreConfiguration  @params   -WorkingDirectory $(Join-Path $PWD "logs") -Verbose
    }
}

Install-SitecoreInstallFramework
Download-Assets
Confirm-Prerequisites
Install-SingleDeveloper
Add-AppPoolMembership
Add-AdditionalBindings

$StopWatch.Stop()
$StopWatch
