Param(
    [string] $ConfigurationFile = "configuration-xp0.json"
)

#####################################################
# 
#  Install Sitecore
# 
#####################################################
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (!(Test-Path $ConfigurationFile)) {
    Write-Host "Configuration file '$($ConfigurationFile)' not found." -ForegroundColor Red
    Write-Host  "Please use 'set-installation...ps1' files to generate a configuration file." -ForegroundColor Red
    Exit 1
}
$config = Get-Content -Raw $ConfigurationFile |  ConvertFrom-Json
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
$resourcePath = Join-Path $PSScriptRoot "Sitecore.WDP.Resources"

Write-Host "*******************************************************" -ForegroundColor Green
Write-Host " Installing Sitecore $($assets.sitecoreVersion)" -ForegroundColor Green
Write-Host " Sitecore: $($site.hostName)" -ForegroundColor Green
Write-Host " xConnect: $($xConnect.siteName)" -ForegroundColor Green
Write-Host "*******************************************************" -ForegroundColor Green


Function Set-ModulesPath {
    Write-Host "Setting Modules Path" -ForegroundColor Green
    $modulesPath = ( Join-Path -Path $resourcePath -ChildPath "Modules" )
    if ($env:PSModulePath -notlike "*$modulesPath*") {
        $p = $env:PSModulePath + ";" + $modulesPath
        [Environment]::SetEnvironmentVariable("PSModulePath", $p)
    }
}
Function Install-SitecoreInstallFramework {
    #Register Assets PowerShell Repository
    if ((Get-PSRepository | Where-Object {$_.Name -eq $assets.psRepositoryName}).count -eq 0) {
        Register-PSRepository -Name $assets.psRepositoryName -SourceLocation $assets.psRepository -InstallationPolicy Trusted 
    }

    #Sitecore Install Framework dependencies
    Import-Module WebAdministration

    #Install SIF
    $module = Get-Module -FullyQualifiedName @{ModuleName = "SitecoreInstallFramework"; ModuleVersion = $($assets.installerVersion -replace "-beta[0-9]*$")}
    if (-not $module) {
        write-host "Installing the Sitecore Install Framework, version $($assets.installerVersion)" -ForegroundColor Green
        Install-Module SitecoreInstallFramework -RequiredVersion $assets.installerVersion -Repository $assets.psRepositoryName -Scope CurrentUser -Force -AllowPrerelease
        Import-Module SitecoreInstallFramework -RequiredVersion $($assets.installerVersion -replace "-beta[0-9]*$")
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
    $credentials = Get-Credential -Message "Please provide dev.sitecore.com credentials"


    $downloadJsonPath = $([io.path]::combine($resourcePath, 'content', 'Deployment', 'OnPrem', 'HabitatHome', 'download-assets.json'))
    Set-Alias sz 'C:\Program Files\7-Zip\7z.exe'
    $package = $modules | Where-Object {$_.id -eq "xp"}
    
    if ($package.download -eq $true) {
        Write-Host ("Downloading {0}  -  if required" -f $package.name )
        
        $destination =  $package.packagePath
            
        if (!(Test-Path $destination)) {
            $params = @{
                Path        = $downloadJsonPath
                Credentials = $credentials
                Source      = $package.url
                Destination = $destination
            }
            Install-SitecoreConfiguration  @params  -WorkingDirectory $(Join-Path $PWD "logs") -Verbose 
        }
        if ((Test-Path $destination) -and ( $package.extract -eq $true)) {
            sz x -o"$DownloadFolder" $destination  -y -aoa
        }
    }
   
    
    # Download Sitecore Azure Toolkit (used for converting modules)
    $package = $modules | Where-Object {$_.id -eq "sat"}
   
    $destination = $package.packagePath
   
    if (!(Test-Path $destination) -and $package.download -eq $true) {
        $params = @{
            Path        = $downloadJsonPath
            Credentials = $credentials
            Source      = $package.url
            Destination = $destination
        }
        Install-SitecoreConfiguration  @params  -WorkingDirectory $(Join-Path $PWD "logs") -Verbose 
    }
    if ((Test-Path $destination) -and ( $package.install -eq $true)) {
        sz x -o"$DownloadFolder\sat" $destination  -y -aoa
    }
}
Function Confirm-Prerequisites {
    #Verify SQL version
    
    [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | out-null
    $srv = New-Object "Microsoft.SqlServer.Management.Smo.Server" $sql.server
    $minVersion = New-Object System.Version($sql.minimumVersion)
    if ($srv.Version.CompareTo($minVersion) -lt 0) {
        throw "Invalid SQL version. Expected SQL 2016 SP1 ($($sql.minimumVersion)) or above."
    }

    #Verify Java version
    
    $minVersion = New-Object System.Version($assets.jreRequiredVersion)
    $foundVersion = $FALSE
   
    
    function getJavaVersions() {
        $versions = '', 'Wow6432Node\' |
            ForEach-Object {Get-ItemProperty -Path HKLM:\SOFTWARE\$($_)Microsoft\Windows\CurrentVersion\Uninstall\* |
                Where-Object {($_.DisplayName -like '*Java *') -and (-not $_.SystemComponent)} |
                Select-Object DisplayName, DisplayVersion, @{n = 'Architecture'; e = {If ($_.PSParentPath -like '*Wow6432Node*') {'x86'} Else {'x64'}}}}
        return $versions
    }
    function checkJavaversion($toVersion) {
        $versions_ = getJavaVersions
        foreach ($version_ in $versions_) {
            try {
                $version = New-Object System.Version($version_.DisplayVersion)
                
            }
            catch {
                continue
            }

            if ($version.CompareTo($toVersion) -ge 0) {
                return $TRUE
            }
        }

        return $false

    }
    
    $foundVersion = checkJavaversion($minversion)
    
    if (-not $foundVersion) {
        throw "Invalid Java version. Expected $minVersion or above."
    }

    # Verify Web Deploy
    $webDeployPath = ([IO.Path]::Combine($env:ProgramFiles, 'iis', 'Microsoft Web Deploy V3', 'msdeploy.exe'))
    if (!(Test-Path $webDeployPath)) {
        throw "Could not find WebDeploy in $webDeployPath"
    }   

  
    
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

    #Verify .NET framework
	
    $versionExists = Get-ChildItem "hklm:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\" | Get-ItemPropertyValue -Name Release | ForEach-Object { $_ -ge $assets.dotnetMinimumVersionValue }
    if (-not $versionExists) {
        throw "Please install .NET Framework $($assets.dotnetMinimumVersion) or newer"
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
Function Install-XConnect {
    #Install xConnect Solr
    try {
        $params = @{
            Path        = $xConnect.solrConfigurationPath 
            SolrUrl     = $solr.url 
            SolrRoot    = $solr.root 
            SolrService = $solr.serviceName 
            CorePrefix  = $site.prefix
        }
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs")
    }
    catch {
        write-host "XConnect SOLR Failed" -ForegroundColor Red
        throw
    }

    #Generate xConnect client certificate
    try {
        Write-Host $xConnect.certificateConfigurationPath
        $params = @{
            Path             = $xConnect.certificateConfigurationPath 
            CertificateName  = $xConnect.certificateName 
            CertPath         = $assets.certificatesPath
            RootCertFileName = $sitecore.rootCertificateName
        }
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs")
    }
    catch {
        write-host "XConnect Certificate Creation Failed" -ForegroundColor Red
        throw
    }

    #Install xConnect
    try {
        $params = @{
            Path                           = $xConnect.ConfigurationPath
            Package                        = $xConnect.PackagePath
            LicenseFile                    = $assets.licenseFilePath
            SiteName                       = $xConnect.siteName
            XConnectCert                   = $xConnect.certificateName
            SqlDbPrefix                    = $site.prefix
            SolrCorePrefix                 = $site.prefix
            SqlAdminUser                   = $sql.adminUser
            SqlAdminPassword               = $sql.adminPassword
            SqlServer                      = $sql.server
            SqlCollectionUser              = $sql.collectionUser
            SqlCollectionPassword          = $sql.collectionPassword
            SqlProcessingPoolsUser         = $sql.processingPoolsUser
            SqlProcessingPoolsPassword     = $sql.processingPoolsPassword
            SqlReferenceDataUser           = $sql.referenceDataUser
            SqlReferenceDataPassword       = $sql.referenceDataPassword
            SqlMarketingAutomationUser     = $sql.marketingAutomationUser
            SqlMarketingAutomationPassword = $sql.marketingAutomationPassword
            SqlMessagingUser               = $sql.messagingUser
            SqlMessagingPassword           = $sql.messagingPassword
            SolrUrl                        = $solr.url
			SqlProcessingEngineUser         = $sql.processingEngineUser
            SqlProcessingEnginePassword     = $sql.processingEnginePassword
            SqlReportingUser               = $sql.reportingUser
            SqlReportingPassword           = $sql.reportingPassword
            MachineLearningServerUrl        = "XXX"
            MachineLearningServerBlobEndpointCertificatePath    = ""
            MachineLearningServerBlobEndpointCertificatePassword = ""
            MachineLearningServerTableEndpointCertificatePath   = ""
            MachineLearningServerTableEndpointCertificatePassword = ""
            MachineLearningServerEndpointCertificationAuthorityCertificatePath = ""
            WebRoot							= $site.webRoot
        }
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs")
    }
    catch {
        write-host "XConnect Setup Failed" -ForegroundColor Red
        throw
    }

    #Set rights on the xDB connection database
    Write-Host "Setting Collection User rights" -ForegroundColor Green
    try {
        $sqlVariables = "DatabasePrefix = $($site.prefix)", "UserName = $($sql.collectionUser)", "Password = $($sql.collectionPassword)"
        Invoke-Sqlcmd -ServerInstance $sql.server `
            -Username $sql.adminUser `
            -Password $sql.adminPassword `
            -InputFile "$PSScriptRoot\database\collectionusergrant.sql" `
            -Variable $sqlVariables
    }
    catch {
        write-host "Set Collection User rights failed" -ForegroundColor Red
        throw
    }
}
Function Install-Sitecore {

    try {
        #Install Sitecore Solr
        $params = @{
            Path        = $sitecore.solrConfigurationPath
            SolrUrl     = $solr.url
            SolrRoot    = $solr.root
            SolrService = $solr.serviceName
            CorePrefix  = $site.prefix
        }
        Install-SitecoreConfiguration  @params -WorkingDirectory $(Join-Path $PWD "logs")
    }
    catch {
        write-host "Sitecore SOLR Failed" -ForegroundColor Red
        throw
    }

    try {
        #Install Sitecore
        $sitecoreParams = @{
            Path                                 = $sitecore.configurationPath
            Package                              = $sitecore.packagePath
            LicenseFile                          = $assets.licenseFilePath
            SiteName                             = $site.hostName
            XConnectCert                         = $xConnect.certificateName
            SqlDbPrefix                          = $site.prefix
            SolrCorePrefix                       = $site.prefix
            SitecoreAdminPassword                = $sitecore.adminPassword
            SqlAdminUser                         = $sql.adminUser
            SqlAdminPassword                     = $sql.adminPassword
            SqlCoreUser                          = $sql.coreUser
            SqlCorePassword                      = $sql.corePassword
            SqlMasterUser                        = $sql.masterUser
            SqlMasterPassword                    = $sql.masterPassword
            SqlWebUser                           = $sql.webUser
            SqlWebPassword                       = $sql.webPassword
            SqlReportingUser                     = $sql.reportingUser
            SqlReportingPassword                 = $sql.reportingPassword
            SqlProcessingPoolsUser               = $sql.processingPoolsUser
            SqlProcessingPoolsPassword           = $sql.processingPoolsPassword
            SqlProcessingTasksUser               = $sql.processingTasksUser
            SqlProcessingTasksPassword           = $sql.processingTasksPassword
            SqlReferenceDataUser                 = $sql.referenceDataUser
            SqlReferenceDataPassword             = $sql.referenceDataPassword
            SqlMarketingAutomationUser           = $sql.marketingAutomationUser
            SqlMarketingAutomationPassword       = $sql.marketingAutomationPassword
            SqlFormsUser                         = $sql.formsUser
            SqlFormsPassword                     = $sql.formsPassword
            SqlExmMasterUser                     = $sql.exmMasterUser
            SqlExmMasterPassword                 = $sql.exmMasterPassword
            SqlMessagingUser                     = $sql.messagingUser
            SqlMessagingPassword                 = $sql.messagingPassword
            SqlServer                            = $sql.server
            EXMCryptographicKey                  = $sitecore.exmCryptographicKey
            EXMAuthenticationKey                 = $sitecore.exmAuthenticationKey
            SolrUrl                              = $solr.url
			XConnectReportingService             = "https://$($xConnect.siteName)" 
            XConnectCollectionService            = "https://$($xConnect.siteName)"
            XConnectReferenceDataService         = "https://$($xConnect.siteName)"
            MarketingAutomationOperationsService = "https://$($xConnect.siteName)"
            MarketingAutomationReportingService  = "https://$($xConnect.siteName)"
            TelerikEncryptionKey                 = $sitecore.telerikEncryptionKey
			SitecoreIdentityAuthority            = $identityServer.url   
            SitecoreIdentitySecret               = $identityServer.clientSecret
            WebRoot                              = $site.webRoot
        }
        Install-SitecoreConfiguration  @sitecoreParams -WorkingDirectory $(Join-Path $PWD "logs")
    }
    catch {
        write-host "Sitecore Setup Failed" -ForegroundColor Red
        throw
    }
}
Function Install-IdentityServer {
    #################################################################
    # Install client certificate for Identity Server
    #################################################################
      
      
    $certParamsForIdentityServer = @{
        Path            = $xConnect.certificateConfigurationPath 
        CertificateName = $identityServer.name
    }
    Install-SitecoreConfiguration @certParamsForIdentityServer -Verbose


    #################################################################
    # Deploy Identity Server
    #################################################################

    $identityParams = @{
        Path                    = $identityServer.configurationPath
        Package                 = $identityServer.packagePath
        SqlDbPrefix             = $site.prefix
        SqlServer               = $sql.server
        SqlCoreUser             = $sql.adminUser
        SqlCorePassword         = $sql.adminPassword
        SitecoreIdentityCert    = $identityServer.name
        Sitename                = $identityServer.Name
        PasswordRecoveryUrl     = ("https:// {0}" -f $site.hostname)
        AllowedCorsOrigins      = $site.hostName
        ClientSecret            = $identityServer.clientSecret
        LicenseFile             = $assets.licenseFilePath 
    }
    Install-SitecoreConfiguration @identityParams -Verbose   
    
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

Set-ModulesPath
Install-SitecoreInstallFramework
Download-Assets
Confirm-Prerequisites
Install-XConnect
Install-Sitecore
Install-IdentityServer
Add-AppPoolMembership