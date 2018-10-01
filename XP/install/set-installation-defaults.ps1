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
$assets.installerVersion = "1.2.1"
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
$site.addSiteBindingWithSSLPath = (Get-ChildItem $pwd -filter "add-new-binding-and-certificate.json" -Recurse).FullName
$site.configureSearchIndexes = (Get-ChildItem $pwd -filter "configure-search-indexes.json" -Recurse).FullName
$site.habitatHomeSslCertificateName = $site.prefix + "." + $site.suffix

Write-Host "Setting default 'SQL' parameters"
$sql = $json.settings.sql
# SQL Settings

$SqlStrongPassword = "Str0NgPA33w0rd!!" # Used for all other services

$sql.server = "."
$sql.adminUser = "sa"
$sql.adminPassword = "12345"
$sql.coreUser = $site.prefix + "coreuser"
$sql.corePassword = $SqlStrongPassword
$sql.masterUser = $site.prefix + "masteruser"
$sql.masterPassword = $SqlStrongPassword
$sql.webUser = $site.prefix + "webuser"
$sql.webPassword = $SqlStrongPassword
$sql.collectionUser = $site.prefix + "collectionuser"
$sql.collectionPassword = $SqlStrongPassword
$sql.reportingUser = $site.prefix + "reportinguser"
$sql.reportingPassword = $SqlStrongPassword
$sql.processingPoolsUser = $site.prefix + "poolsuser"
$sql.processingPoolsPassword = $SqlStrongPassword
$sql.processingTasksUser = $site.prefix + "tasksuser"
$sql.processingTasksPassword = $SqlStrongPassword
$sql.referenceDataUser = $site.prefix + "referencedatauser"
$sql.referenceDataPassword = $SqlStrongPassword
$sql.marketingAutomationUser = $site.prefix + "marketingautomationuser"
$sql.marketingAutomationPassword = $SqlStrongPassword
$sql.formsUser = $site.prefix + "formsuser"
$sql.formsPassword = $SqlStrongPassword
$sql.exmMasterUser = $site.prefix + "exmmasteruser"
$sql.exmMasterPassword = $SqlStrongPassword
$sql.messagingUser = $site.prefix + "messaginguser"
$sql.messagingPassword = $SqlStrongPassword
$sql.minimumVersion = "13.0.4001"

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

Write-Host "Setting default 'Sitecore' parameters"
# Sitecore Parameters
$sitecore = $json.settings.sitecore
$sitecore.solrConfigurationPath = (Get-ChildItem $pwd -filter "sitecore-solr.json" -Recurse).FullName
$sitecore.configurationPath = (Get-ChildItem $pwd -filter "sitecore-xp0.json" -Recurse).FullName
$sitecore.sslConfigurationPath = "$PSScriptRoot\certificates\sitecore-ssl.json"
$sitecore.packagePath = Join-Path $assets.root $("Sitecore " + $assets.sitecoreVersion + " (OnPrem)_single.scwdp.zip")
$sitecore.siteRoot = Join-Path $site.webRoot -ChildPath $site.hostName
$sitecore.adminPassword = "b"
$sitecore.exmCryptographicKey = "0x0000000000000000000000000000000000000000000000000000000000000000"
$sitecore.exmAuthenticationKey = "0x0000000000000000000000000000000000000000000000000000000000000000"
$sitecore.telerikEncryptionKey = "PutYourCustomEncryptionKeyHereFrom32To256CharactersLong"
$sitecore.rootCertificateName = "SitecoreRoot90"

Write-Host "Setting default 'Solr' parameters"
# Solr Parameters
$solr = $json.settings.solr
$solr.url = "https://localhost:8662/solr"
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
        $module.fileName = (Join-Path $root ("\{0}" -f $module.fileName))    
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