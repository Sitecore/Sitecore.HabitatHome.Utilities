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
$assets.commerce.nugetPackageLocation = "http://nuget1ca2/nuget/Commerce/"
$assets.commerce.nugetPackageName = "Sitecore.Commerce.ReleasePackage.Content"
$assets.commerce.nugetPackageVersion = "2.2.124"
$assets.commerce.packageUrl = "https://v9assets.blob.core.windows.net/v9-onprem-assets/Sitecore.Commerce.2018.05-2.2.63.zip?sv=2017-04-17&ss=bfqt&srt=sco&sp=rwdlacup&se=2027-11-09T20%3A11%3A50Z&st=2017-11-09T12%3A11%3A50Z&spr=https&sig=naspk%2BQflDLjyuC6gfXw4OZKvhhxzTlTvDctfw%2FByj8%3D"
$assets.commerce.installationFolder = Join-Path $assets.root "Commerce"


#Commerce Files to Extract
$sifCommerceVersion = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "SIF.Sitecore.Commerce"} 
$sifCommerceVersion.version = "1.2.14"
$assets.commerce.sifCommerceRoot = Join-Path $assets.commerce.installationFolder $($sifCommerceVersion.name + "." + $sifCommerceVersion.version)
$commerceEngineVersion = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "Sitecore.Commerce.Engine"} 
$commerceEngineVersion.version = "2.2.124"

$commerceEngineSDKVersion = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "Sitecore.Commerce.Engine.SDK"} 
$commerceEngineSDKVersion.version = "2.2.72"

$bizFxVersion = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "Sitecore.BizFX"} 
$bizFxVersion.version = "1.2.19"

# Settings
$site = $json.settings.site
# Commerce Settings
$commerce = $json.settings.commerce
$commerce.storefrontPrefix = $site.habitatHomePrefix
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
