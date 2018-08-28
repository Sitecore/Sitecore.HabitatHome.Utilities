Param(
    [string] $ConfigurationFile = "configuration-xp0.json"
)

Write-Host "Setting Defaults and creating $ConfigurationFile"

$json = Get-Content -Raw .\install-settings.json -Encoding Ascii |  ConvertFrom-Json

Write-host "Setting default 'Assets and prerequisites' parameters"

$assets = $json.assets
$assets.root = "$PSScriptRoot\assets"
$assets.psRepository = "https://sitecore.myget.org/F/sc-powershell/api/v2/"
$assets.psRepositoryName = "SitecoreGallery"
$assets.licenseFilePath = Join-Path $assets.root "license.xml"
$assets.installerVersion = "2.0.0-beta0229"
$assets.sitecoreVersion = "9.1.0 rev. 001256"
$assets.identityServerVersion = "2.0.0 rev. 00128"
$assets.certificatesPath = Join-Path $assets.root "Certificates"
$assets.jreRequiredVersion = "8.0.1710"
$assets.dotnetMinimumVersionValue = "394802"
$assets.dotnetMinimumVersion = "4.7.1"
$assets.installPackagePath = Join-Path $assets.root "installpackage.aspx"

# Settings
Write-Host "Setting default 'Site' parameters"
# Site Settings
$site = $json.settings.site
$site.prefix = "habitathome"
$site.suffix = "dev.local"
$site.webroot = "C:\inetpub\wwwroot"
$site.hostName = $json.settings.site.prefix + "." + $json.settings.site.suffix
$site.enableInstallationImprovements = (Get-ChildItem $pwd -filter "enable-installation-improvements.json" -Recurse).FullName
$site.disableInstallationImprovements = (Get-ChildItem $pwd -filter "disable-installation-improvements.json" -Recurse).FullName
$site.addSiteBindingWithSSLPath = (Get-ChildItem $pwd -filter "add-new-binding-and-certificate.json" -Recurse).FullName
$site.configureSearchIndexes = (Get-ChildItem $pwd -filter "configure-search-indexes.json" -Recurse).FullName
$site.habitatHomeSslCertificateName = $site.prefix + "." + $site.suffix

Write-Host "Setting default 'SQL' parameters"
$sql = $json.settings.sql
# SQL Settings
$sql.server = "."
$sql.adminUser = "sa"
$sql.adminPassword = "12345"
$sql.minimumVersion="13.0.4001"

Write-Host "Setting default 'xConnect' parameters"
# XConnect Parameters
$xConnect = $json.settings.xConnect

$xConnect.ConfigurationPath = (Get-ChildItem $pwd -filter "xconnect-xp0.json" -Recurse).FullName 
$xConnect.certificateConfigurationPath = (Get-ChildItem $pwd -filter "xconnect-createcert.json" -Recurse).FullName
$xConnect.solrConfigurationPath = (Get-ChildItem $pwd -filter "xconnect-solr.json" -Recurse).FullName 
$xConnect.packagePath = Join-Path $assets.root $("Sitecore " + $assets.sitecoreVersion + " (OnPrem)_xp0xconnect.scwdp.zip")
$xConnect.siteName = $site.prefix + "_xconnect." + $site.suffix
$xConnect.certificateName = [string]::Join(".", @($site.prefix, $site.suffix, "xConnect.Client"))
$xConnect.siteRoot = Join-Path $site.webRoot -ChildPath $xConnect.siteName
$xConnect.sqlCollectionUser = $site.prefix + "collectionuser"
$xConnect.sqlCollectionPassword = "Test12345"

Write-Host "Setting default 'Sitecore' parameters"

# Sitecore Parameters
$sitecore = $json.settings.sitecore

$sitecore.solrConfigurationPath =  (Get-ChildItem $pwd -filter "sitecore-solr.json" -Recurse).FullName 
$sitecore.configurationPath = (Get-ChildItem $pwd -filter "sitecore-xp0.json" -Recurse).FullName 
$sitecore.sslConfigurationPath = "$PSScriptRoot\certificates\sitecore-ssl.json"
$sitecore.packagePath = Join-Path $assets.root $("Sitecore " + $assets.sitecoreVersion +" (OnPrem)_single.scwdp.zip")
$sitecore.siteRoot = Join-Path $site.webRoot -ChildPath $site.hostName

Write-Host "Setting default 'IdentityServer' parameters"
$identityServer = $json.settings.identityServer
$identityServer.packagePath = Join-Path $assets.root $("Sitecore.IdentityServer " + $assets.identityServerVersion + " (OnPrem)_identityserver.scwdp.zip")
$identityServer.configurationPath = (Get-ChildItem $pwd -filter "IdentityServer.json" -Recurse).FullName 
$identityServer.name = "IdentityServer." + $site.hostname
$identityServer.url = ("https://{0}" -f $identityServer.name)
$identityServer.clientSecret = "ClientSecret"
Write-Host "Setting default 'Solr' parameters"
# Solr Parameters
$solr = $json.settings.solr
$solr.url = "https://localhost:8983/solr"
$solr.root = "c:\solr"
$solr.serviceName = "Solr"

Write-Host "Setting default 'modules' parameters"
$modules = $json.modules

$spe = $modules | Where-Object { $_.id -eq "spe"}
$spe.packagePath = Join-Path $assets.root "packages\Sitecore PowerShell Extensions-4.7.2 for Sitecore 8.zip"
$spe.install = $true

$sxa = $modules | Where-Object { $_.id -eq "sxa"}
$sxa.packagePath = Join-Path $assets.root "packages\Sitecore Experience Accelerator 1.8 .878 for 9.1.zip"
$sxa.install = $true

$def = $modules | Where-Object {$_.id -eq "def"}
$def.packagePath = Join-Path $assets.root "packages\Data Exchange Framework 2.0.1 rev. 180108.zip"
$def.install = $false

$defSql = $modules | Where-Object {$_.id -eq "defSql"}
$defSql.packagePath = Join-Path $assets.root "packages\SQL Provider for Data Exchange Framework 2.0.1 rev. 180108.zip"
$defSql.install = $false

$defSitecore = $modules | Where-Object {$_.id -eq "defSitecore"}
$defSitecore.packagePath = Join-Path $assets.root "packages\Sitecore Provider for Data Exchange Framework 2.0.1 rev. 180108.zip"
$defSitecore.install = $false

$defxConnect = $modules | Where-Object {$_.id -eq "defxConnect"}
$defxConnect.packagePath = Join-Path $assets.root "packages\xConnect Provider for Data Exchange Framework 2.0.1 rev. 180108.zip"
$defxConnect.install = $false

$defDynamicsProvider = $modules | Where-Object {$_.id -eq "defDynamicsProvider"}
$defDynamicsProvider.packagePath = Join-Path $assets.root "packages\Dynamics Provider for Data Exchange Framework 2.0.1 rev. 180108.zip"
$defDynamicsProvider.install = $false

$defDynamicsConnect = $modules | Where-Object {$_.id -eq "defDynamicsConnect"}
$defDynamicsConnect.packagePath = Join-Path $assets.root "packages\Connect for Microsoft Dynamics 2.0.1 rev. 180108.zip"
$defDynamicsConnect.install = $false

Write-Host ("Saving Configuration file to {0}" -f $ConfigurationFile)

Set-Content $ConfigurationFile  (ConvertTo-Json -InputObject $json -Depth 3 )