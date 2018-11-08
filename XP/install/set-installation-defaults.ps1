Param(
    [string] $ConfigurationFile = "configuration-xp0.json"
)

Write-Host "Setting Defaults and creating $ConfigurationFile"

$json = Get-Content -Raw .\install-settings.json -Encoding Ascii |  ConvertFrom-Json

Write-host "Setting default 'Assets and prerequisites' parameters"

$assets = $json.assets
$assets.root = "$PSScriptRoot\assets"
# SIF settings
$assets.psRepository = "https://sitecore.myget.org/F/sc-powershell/api/v2/"
$assets.psRepositoryName = "SitecoreGallery"
$assets.installerVersion = "2.0.1"

$assets.licenseFilePath = Join-Path $assets.root "license.xml"

$assets.sitecoreVersion = "9.1.0 rev. 001564"
$assets.identityServerVersion = "2.0.1 rev. 00158"


$assets.certificatesPath = Join-Path $assets.root "Certificates"

# Settings
Write-Host "Setting default 'Site' parameters"
# Site Settings
$site = $json.settings.site
$site.prefix = "habitathome"
$site.suffix = "dev.local"
$site.webroot = "C:\inetpub\wwwroot"
$site.hostName = $json.settings.site.prefix + "." + $json.settings.site.suffix

Write-Host "Setting default 'SQL' parameters"
$sql = $json.settings.sql
# SQL Settings

$SqlStrongPassword = "Str0NgPA33w0rd!!" # Used for all other services

$sql.server = "."
$sql.adminUser = "sa"
$sql.adminPassword = "Str0NgPA33w0rd!!"
$sql.userPassword = $SqlStrongPassword
$sql.coreUser =  "coreuser"
$sql.corePassword = $SqlStrongPassword
$sql.masterUser =  "masteruser"
$sql.masterPassword = $SqlStrongPassword
$sql.webUser =  "webuser"
$sql.webPassword = $SqlStrongPassword
$sql.collectionUser =  "collectionuser"
$sql.collectionPassword = $SqlStrongPassword
$sql.reportingUser =  "reportinguser"
$sql.reportingPassword = $SqlStrongPassword
$sql.processingPoolsUser =  "poolsuser"
$sql.processingPoolsPassword = $SqlStrongPassword
$sql.processingEngineUser =  "processingengineuser"
$sql.processingEnginePassword = $SqlStrongPassword
$sql.processingTasksUser =  "tasksuser"
$sql.processingTasksPassword = $SqlStrongPassword
$sql.referenceDataUser =  "referencedatauser"
$sql.referenceDataPassword = $SqlStrongPassword
$sql.marketingAutomationUser =  "marketingautomationuser"
$sql.marketingAutomationPassword = $SqlStrongPassword
$sql.formsUser =  "formsuser"
$sql.formsPassword = $SqlStrongPassword
$sql.exmMasterUser =  "exmmasteruser"
$sql.exmMasterPassword = $SqlStrongPassword
$sql.messagingUser =  "messaginguser"
$sql.messagingPassword = $SqlStrongPassword
$sql.securityuser =  "securityuser"
$sql.securityPassword = $SqlStrongPassword
$sql.minimumVersion = "13.0.4001"

Write-Host "Setting default 'xConnect' parameters"
# XConnect Parameters
$xConnect = $json.settings.xConnect
$xConnect.ConfigurationPath = (Get-ChildItem $pwd -filter "xconnect-xp0.json" -Recurse).FullName
$xConnect.certificateConfigurationPath = (Get-ChildItem $pwd -filter "createcert.json" -Recurse).FullName
$xConnect.solrConfigurationPath = (Get-ChildItem $pwd -filter "xconnect-solr.json" -Recurse).FullName
$xConnect.packagePath = Join-Path $assets.root $("Sitecore " + $assets.sitecoreVersion + " (OnPrem)_xp0xconnect.scwdp.zip")
$xConnect.siteName = $site.prefix + "_xconnect." + $site.suffix
$xConnect.certificateName = [string]::Join(".", @($site.prefix, $site.suffix, ".Client"))
$xConnect.siteRoot = Join-Path $site.webRoot -ChildPath $xConnect.siteName

Write-Host "Setting default 'Sitecore' parameters"
# Sitecore Parameters
$sitecore = $json.settings.sitecore
$sitecore.solrConfigurationPath = (Get-ChildItem $pwd -filter "sitecore-solr.json" -Recurse).FullName
$sitecore.singleDeveloperConfigurationPath = (Get-ChildItem $pwd -filter "XP0-SingleDeveloper.json" -Recurse).FullName
$sitecore.sslConfigurationPath = "$PSScriptRoot\certificates\sitecore-ssl.json"
$sitecore.packagePath = Join-Path $assets.root $("Sitecore " + $assets.sitecoreVersion + " (OnPrem)_single.scwdp.zip")
$sitecore.adminPassword = "b"
$sitecore.exmCryptographicKey = "0x0000000000000000000000000000000000000000000000000000000000000000"
$sitecore.exmAuthenticationKey = "0x0000000000000000000000000000000000000000000000000000000000000000"
$sitecore.telerikEncryptionKey = "PutYourCustomEncryptionKeyHereFrom32To256CharactersLong"
$sitecore.rootCertificateName = "SitecoreRoot91"
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
$solr.url = "https://localhost:8721/solr"
$solr.root = "c:\solr"
$solr.serviceName = "Solr"

Write-Host "Setting default 'modules' parameters"
# Modules
$modulesConfig = Get-Content -Raw .\assets.json -Encoding Ascii |  ConvertFrom-Json

$modules = $json.modules

$sitecore = $modulesConfig.sitecore

$config = @{
    id          = $sitecore.id
    name        = $sitecore.name
    fileName    = Join-Path $assets.root ("\{0}" -f $sitecore.fileName) 
    url         = $sitecore.url
    extract     = $sitecore.extract
    download    = $sitecore.download
    source      = $sitecore.source
}
$config = $config| ConvertTo-Json
$modules += (ConvertFrom-Json -InputObject $config) 

Function Replace-Path {
    param(
        $module,
        $root
    )
    if ($module.isGroup) {
        foreach ($module in $module.modules) {
            Replace-Path $module $root
        }
    }
    else {
        $module.fileName = (Join-Path $root ("\packages\{0}" -f $module.fileName))    
    }
}

$json.modules = $modules

foreach ($module in $modulesConfig.modules) {
    Replace-Path $module $assets.root
}
$modules += $modulesConfig.modules
$json.modules = $modules


Write-Host ("Saving Configuration file to {0}" -f $ConfigurationFile)

Set-Content $ConfigurationFile  (ConvertTo-Json -InputObject $json -Depth 6 )