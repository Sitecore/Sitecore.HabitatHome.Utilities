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
$assets.sitecoreVersion = "9.0.2 rev. 180604"
$assets.installerVersion = "1.2.0"
$assets.certificatesPath = Join-Path $assets.root "Certificates"
$assets.jreRequiredVersion = "8.0.1510"
$assets.dotnetMinimumVersionValue = "394802"
$assets.dotnetMinimumVersion = "4.6.2"
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
$sxa.packagePath = Join-Path $assets.root "packages\Sitecore Experience Accelerator 1.7.1 rev. 180604 for 9.0.zip"
$sxa.install = $true

$def = $modules | Where-Object {$_.id -eq "def"}
$def.packagePath = Join-Path $assets.root "packages\Data Exchange Framework 2.0.1 rev. 180108.zip"
$def.install = $true

$defSql = $modules | Where-Object {$_.id -eq "defSql"}
$defSql.packagePath = Join-Path $assets.root "packages\SQL Provider for Data Exchange Framework 2.0.1 rev. 180108.zip"
$defSql.install = $true

$defSitecore = $modules | Where-Object {$_.id -eq "defSitecore"}
$defSitecore.packagePath = Join-Path $assets.root "packages\Sitecore Provider for Data Exchange Framework 2.0.1 rev. 180108.zip"
$defSitecore.install = $true

$defxConnect = $modules | Where-Object {$_.id -eq "defxConnect"}
$defxConnect.packagePath = Join-Path $assets.root "packages\xConnect Provider for Data Exchange Framework 2.0.1 rev. 180108.zip"
$defxConnect.install = $true

$defDynamicsProvider = $modules | Where-Object {$_.id -eq "defDynamicsProvider"}
$defDynamicsProvider.packagePath = Join-Path $assets.root "packages\Dynamics Provider for Data Exchange Framework 2.0.1 rev. 180108.zip"
$defDynamicsProvider.install = $true

$defDynamicsConnect = $modules | Where-Object {$_.id -eq "defDynamicsConnect"}
$defDynamicsConnect.packagePath = Join-Path $assets.root "packages\Connect for Microsoft Dynamics 2.0.1 rev. 180108.zip"
$defDynamicsConnect.install = $true

Write-Host ("Saving Configuration file to {0}" -f $ConfigurationFile)

Set-Content $ConfigurationFile  (ConvertTo-Json -InputObject $json -Depth 3 )