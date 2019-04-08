Param(
    [string] $ConfigurationFile = "configuration-xp0.json",
	[string] $assetsRoot,
    [string] $sitecoreVersion
)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "Setting Defaults and creating $ConfigurationFile"

$json = Get-Content -Raw .\install-settings.json -Encoding Ascii |  ConvertFrom-Json

Write-host "Setting default 'Assets and prerequisites' parameters"

$assets = $json.assets

if (![string]::IsNullOrEmpty($assetsRoot)) {
    $assets.root = $assetsRoot
}
else {
    $assets.root = "$PSScriptRoot\assets"
}
$baseConfiguration = Join-Path $assets.root "configuration\XP0"

if (![string]::IsNullOrEmpty($sitecoreVersion)) {
    $assets.sitecoreVersion = $sitecoreVersion
}
else {
    $assets.sitecoreVersion = "9.1.0 rev. 001564"
}
# SIF settings
$assets.psRepository = "https://sitecore.myget.org/F/sc-powershell/api/v2/"
$assets.psRepositoryName = "SitecoreGallery"
$assets.installerVersion = "2.0.0"
$assets.sharedUtilitiesRoot = (Resolve-Path "..\..\Shared" | Select-Object -ExpandProperty Path)
$assets.sitecoreazuretoolkit = Join-Path $assets.sharedUtilitiesRoot "sat"
$assets.licenseFilePath = Join-Path $assets.root "license.xml"

$assets.sitecoreVersion = "9.1.0 rev. 001564"
$assets.identityServerVersion = "2.0.0 rev. 00157"


$assets.certificatesPath = Join-Path $assets.sharedUtilitiesRoot "Certificates"

# Settings
Write-Host "Setting default 'Site' parameters"
# Site Settings
$site = $json.settings.site
$site.prefix = "habitathome"
$site.suffix = "dev.local"
$site.webroot = "C:\inetpub\wwwroot"
$site.hostName = $json.settings.site.prefix + "." + $json.settings.site.suffix
$site.addSiteBindingWithSSLPath = (Get-ChildItem $assets.sharedUtilitiesRoot -filter "add-new-binding-and-certificate.json" -Recurse).FullName


Write-Host "Setting default 'SQL' parameters"
$sql = $json.settings.sql
# SQL Settings

$SqlStrongPassword = "Str0NgPA33w0rd!!" # Used for all other services

$sql.server = "."
$sql.adminUser = "sa"
$sql.adminPassword = "Str0NgPA33w0rd!!"
$sql.userPassword = $SqlStrongPassword
$sql.coreUser = "coreuser"
$sql.corePassword = $SqlStrongPassword
$sql.masterUser = "masteruser"
$sql.masterPassword = $SqlStrongPassword
$sql.webUser = "webuser"
$sql.webPassword = $SqlStrongPassword
$sql.collectionUser = "collectionuser"
$sql.collectionPassword = $SqlStrongPassword
$sql.reportingUser = "reportinguser"
$sql.reportingPassword = $SqlStrongPassword
$sql.processingPoolsUser = "poolsuser"
$sql.processingPoolsPassword = $SqlStrongPassword
$sql.processingEngineUser = "processingengineuser"
$sql.processingEnginePassword = $SqlStrongPassword
$sql.processingTasksUser = "tasksuser"
$sql.processingTasksPassword = $SqlStrongPassword
$sql.referenceDataUser = "referencedatauser"
$sql.referenceDataPassword = $SqlStrongPassword
$sql.marketingAutomationUser = "marketingautomationuser"
$sql.marketingAutomationPassword = $SqlStrongPassword
$sql.formsUser = "formsuser"
$sql.formsPassword = $SqlStrongPassword
$sql.exmMasterUser = "exmmasteruser"
$sql.exmMasterPassword = $SqlStrongPassword
$sql.messagingUser = "messaginguser"
$sql.messagingPassword = $SqlStrongPassword
$sql.securityuser = "securityuser"
$sql.securityPassword = $SqlStrongPassword
$sql.minimumVersion = "13.0.4001"

Write-Host "Setting default 'xConnect' parameters"
# XConnect Parameters
$xConnect = $json.settings.xConnect
$xConnect.ConfigurationPath = (Get-ChildItem $baseConfiguration -filter "xconnect-xp0.json" -Recurse).FullName
$xConnect.certificateConfigurationPath = (Get-ChildItem $baseConfiguration -filter "createcert.json" -Recurse).FullName
$xConnect.solrConfigurationPath = (Get-ChildItem $baseConfiguration -filter "xconnect-solr.json" -Recurse).FullName
$xConnect.packagePath = Join-Path $assets.root $("Sitecore " + $assets.sitecoreVersion + " (OnPrem)_xp0xconnect.scwdp.zip")
$xConnect.siteName = $site.prefix + "_xconnect." + $site.suffix
$xConnect.siteRoot = Join-Path $site.webRoot -ChildPath $xConnect.siteName

Write-Host "Setting default 'Sitecore' parameters"
# Sitecore Parameters
$sitecore = $json.settings.sitecore
$sitecore.solrConfigurationPath = (Get-ChildItem $baseConfiguration -filter "sitecore-solr.json" -Recurse).FullName
$sitecore.singleDeveloperConfigurationPath = (Get-ChildItem $baseConfiguration -filter "XP0-SingleDeveloper.json" -Recurse).FullName
$sitecore.sslConfigurationPath = "$($baseConfiguration)\certificates\sitecore-ssl.json"
$sitecore.packagePath = Join-Path $assets.root $("Sitecore " + $assets.sitecoreVersion + " (OnPrem)_single.scwdp.zip")
$sitecore.adminPassword = "b"
$sitecore.exmCryptographicKey = "0x0000000000000000000000000000000000000000000000000000000000000000"
$sitecore.exmAuthenticationKey = "0x0000000000000000000000000000000000000000000000000000000000000000"
$sitecore.telerikEncryptionKey = "PutYourCustomEncryptionKeyHereFrom32To256CharactersLong"
$sitecore.rootCertificateName = "SitecoreRoot91"
Write-Host "Setting default 'IdentityServer' parameters"
$identityServer = $json.settings.identityServer
$identityServer.packagePath = Join-Path $assets.root $("Sitecore.IdentityServer " + $assets.identityServerVersion + " (OnPrem)_identityserver.scwdp.zip")
$identityServer.configurationPath = (Get-ChildItem $baseConfiguration -filter "IdentityServer.json" -Recurse).FullName 
$identityServer.name = $site.prefix + "_identityserver-" + $site.suffix
$identityServer.url = ("https://{0}" -f $identityServer.name)
$identityServer.clientSecret = "ClientSecret"

Write-Host "Setting default 'Solr' parameters"
# Solr Parameters
$solr = $json.settings.solr
$solr.url = "https://localhost:8721/solr"
$solr.root = "c:\solr"
$solr.serviceName = "Solr"

Write-Host ("Saving Configuration file to {0}" -f $ConfigurationFile)

Set-Content $ConfigurationFile  (ConvertTo-Json -InputObject $json -Depth 6 )