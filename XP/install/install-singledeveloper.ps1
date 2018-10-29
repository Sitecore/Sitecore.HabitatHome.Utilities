Param(
    [string] $ConfigurationFile = "configuration-xp0.json",
    [string] $LogFolder = ".\logs\",
    [string] $LogFileName = "install-sitecore.log"
)

#####################################################
# 
#  Install Sitecore
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

$site = $config.settings.site
$sql = $config.settings.sql
$xConnect = $config.settings.xConnect
$sitecore = $config.settings.sitecore
$identityServer = $config.settings.identityServer
$solr = $config.settings.solr
$assets = $config.assets
$modules = $config.modules
$resourcePath = Join-Path $assets.root "configuration"

Write-Host "*******************************************************" -ForegroundColor Green
Write-Host " Installing Sitecore" -ForegroundColor Green
Write-Host " Sitecore: $($site.hostName)" -ForegroundColor Green
Write-Host " xConnect: $($xConnect.siteName)" -ForegroundColor Green
Write-Host "*******************************************************" -ForegroundColor Green


# Function Set-ModulesPath {
#     Write-Host "Setting Modules Path" -ForegroundColor Green
#     $modulesPath = ( Join-Path -Path $resourcePath -ChildPath "Modules" )
#     if ($env:PSModulePath -notlike "*$modulesPath*") {
#         $p = $env:PSModulePath + ";" + $modulesPath
#         [Environment]::SetEnvironmentVariable("PSModulePath", $p)
#     }
# }
Function Install-SitecoreInstallFramework {
    #Register Assets PowerShell Repository
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
        Install-Module SitecoreInstallFramework -RequiredVersion $assets.installerVersion -Repository $assets.psRepositoryName -Scope CurrentUser -Force -AllowPrerelease
        Import-Module SitecoreInstallFramework -RequiredVersion $sifVersion
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
        
        $destination = $package.fileName
            
        if (!(Test-Path $destination)) {
            $params = @{
                Path        = $downloadJsonPath
                Credentials = $credentials
                Source      = $package.url
                Destination = $destination
            }
            Install-SitecoreConfiguration  @params  *>&1 | Tee-Object $LogFile -Append 
        }
        if ((Test-Path $destination) -and ( $package.extract -eq $true)) {
            sz x -o"$DownloadFolder" $destination  -y -aoa
        }
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
        Path                          = $sitecore.singleDeveloperConfigurationPath
        SqlServer                     = $sql.server
        SqlAdminUser                  = $sql.adminUser
        SqlAdminPassword              = $sql.adminPassword
        SitecoreAdminPassword         = $sitecore.adminPassword
        SolrUrl                       = $solr.url
        SolrRoot                      = $solr.root
        SolrService                   = $solr.serviceName
        Prefix                        = $site.hostName
        XConnectCertificateName       = $xconnect.siteName
        IdentityServerCertificateName = $identityServer.name
        IdentityServerSiteName        = $identityServer.name
        LicenseFile                   = $assets.licenseFilePath
        XConnectPackage               = $xConnect.packagePath
        SitecorePackage               = $sitecore.packagePath
        IdentityServerPackage         = $identityServer.packagePath
        XConnectSiteName              = $xConnect.siteName
        SitecoreSitename              = $site.hostName
        PasswordRecoveryUrl           = "https://" + $site.hostName
        SitecoreIdentityAuthority     = "https://" + $identityServer.name
        XConnectCollectionService     = "https://" + $xConnect.siteName
        ClientSecret                  = $identityServer.clientSecret
        AllowedCorsOrigins            = "https://" + $site.hostName
    }

    Push-Location $resourcePath
    Try{
        Install-SitecoreConfiguration @singleDeveloperParams   *>&1 | Tee-Object XP0-SingleDeveloper.log
    }
    Catch{
        Pop-Location
        Exit 1
    }
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

Install-SitecoreInstallFramework
Download-Assets
Confirm-Prerequisites
Install-SingleDeveloper
Add-AppPoolMembership