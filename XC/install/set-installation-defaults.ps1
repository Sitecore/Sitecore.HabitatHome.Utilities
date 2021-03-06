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
$assets.downloadFolder =  $assets.packageRepository

#Commerce
$assets.commerce.packageName = "Sitecore.Commerce.WDP.2020.01-5.0.145.zip"
$assets.commerce.packageUrl = "https://dev.sitecore.net/~/media/B915EEE9B5C0429AB557C357E2B23EEA.ashx"
$assets.commerce.installationFolder = Join-Path $assets.packageRepository "Commerce"


#Commerce Files to Extract
$sifCommerceVersion = $assets.commerce.filesToExtract | Where-Object { $_.name -eq "SIF.Sitecore.Commerce"}
$sifCommerceVersion.version = "4.0.31"

$assets.commerce.sifCommerceRoot = Join-Path $assets.commerce.installationFolder $($sifCommerceVersion.name + "." + $sifCommerceVersion.version)

# Settings
$site = $json.settings.site
# Commerce Settings
$commerce = $json.settings.commerce
$commerce.engineConfigurationPath = ([IO.Path]::Combine($assets.root, "Resources","Configuration","Commerce","HabitatHome","set-engine-hostname.json"))
$commerce.storefrontPrefix = $site.prefix
$commerce.storefrontHostName = $commerce.storefrontPrefix + "." + $site.suffix

$commerce.engineConnectClientId = "CommerceEngineConnect"
$commerce.engineConnectClientSecret = "J6qfqaKX1hAFIUjiNCAV6jVolLqwhF4OgM6dHT7c9dk="

$commerce.serviceAccountDomain = "$($Env:COMPUTERNAME)"
$commerce.serviceAccountUserName = "CSFndRuntimeUser"
$commerce.serviceAccountPassword = "Pu8azaCr"
$commerce.brainTreeAccountMerchandId = ""
$commerce.brainTreeAccountPublicKey = ""
$commerce.brainTreeAccountPrivateKey = ""
$commerce.brainTreeEnvironment = ""

# Site Settings
$site = $json.settings.site

Write-Host
Write-Host "Saving content to $ConfigurationFile" -ForegroundColor Green
Set-Content $ConfigurationFile  (ConvertTo-Json -InputObject $json -Depth 4 )
