Param(
    [string] $ConfigurationFile = "configuration-xc0.json",
    [string] $XPConfigurationFile = (Resolve-Path "..\..\xp\install\configuration-xp0.json")
)

Write-Host "Setting Defaults and creating $ConfigurationFile" -foregroundColor Green

$json = Get-Content -Raw .\install-settings.json -Encoding Ascii |  ConvertFrom-Json
$assetsPath = Join-Path "$PWD" "assets"
[System.Reflection.Assembly]::LoadFile($(Join-Path $assetsPath "Newtonsoft.Json.dll"))
[System.Reflection.Assembly]::LoadFile($(Join-Path $assetsPath "JsonMerge.dll"))
$installSettingsPath = $(Join-Path $PWD  ".\install-settings.json" -Resolve)
$json = [JsonMerge.JsonMerge]::MergeJson($XPConfigurationFile, $installSettingsPath  ) | ConvertFrom-Json

# Assets and prerequisites

$assets = $json.assets
$assets.root = "$PSScriptRoot\assets"
$assets.downloadFolder = Join-Path $assets.root "Downloads"

#Commerce
$assets.commerce.packageName = "Sitecore.Commerce.2018.07-2.2.126.zip"
$assets.commerce.packageUrl = "https://dev.sitecore.net/~/media/F374366CA5C649C99B09D35D5EF1BFCE.ashx"
$assets.commerce.installationFolder = Join-Path $assets.root "Commerce"


#Commerce Files to Extract
$sifCommerceVersion = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "SIF.Sitecore.Commerce"} 
$sifCommerceVersion.version = "1.2.14"

$assets.commerce.sifCommerceRoot = Join-Path $assets.commerce.installationFolder $($sifCommerceVersion.name + "." + $sifCommerceVersion.version)

$commerceEngineVersion = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "Sitecore.Commerce.Engine"} 
$commerceEngineVersion.version = "2.2.126"

$commerceEngineSDKVersion = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "Sitecore.Commerce.Engine.SDK"} 
$commerceEngineSDKVersion.version = "2.2.72"

$bizFxVersion = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "Sitecore.BizFX"} 
$bizFxVersion.version = "1.2.19"

$identityServerVersion = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "Sitecore.IdentityServer"} 
$identityServerVersion.version = "1.2.3"

# Settings
$site = $json.settings.site
# Commerce Settings
$commerce = $json.settings.commerce
$commerce.engineConfigurationPath = ([IO.Path]::Combine($assets.root, "Resources","Configuration","Commerce","HabitatHome","set-engine-hostname.json"))
$commerce.storefrontPrefix = $site.prefix
$commerce.storefrontHostName = $commerce.storefrontPrefix + "." + $site.suffix

$commerce.serviceAccountDomain = "$($Env:COMPUTERNAME)"
$commerce.serviceAccountUserName = "CSFndRuntimeUser"
$commerce.serviceAccountPassword = "Pu8azaCr"
$commerce.brainTreeAccountMerchandId = ""
$commerce.brainTreeAccountPublicKey = ""
$commerce.brainTreeAccountPrivateKey = ""
$commerce.identityServerName = "SitecoreIdentityServer"

# Site Settings
$site = $json.settings.site


# Sitecore Parameters
$sitecore = $json.settings.sitecore
$json.modules = ""

# Solr Parameters
$solr = $json.settings.solr
Write-Host
Write-Host "Saving content to $ConfigurationFile" -ForegroundColor Green
Set-Content $ConfigurationFile  (ConvertTo-Json -InputObject $json -Depth 4 )
