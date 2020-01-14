# Credit primarily to jermdavis for the original script

Param(
	[string] $ConfigurationFile = "configuration-xp0.json",
	[string]$solrVersion = "8.1.1",
	[string]$installFolder = "c:\solr",
	[string]$solrPort = "8811",
	[string]$solrHost = "localhost",
	[bool]$solrSSL = $TRUE,
	[string]$keystoreSecret = "secret",
	[string]$KeystoreFile = 'solr-ssl.keystore.jks',
	[string]$SolrDomain = 'localhost',
	[string]$maxJvmMem = '512m',
	[switch]$Clobber,
	[switch]$Uninstall
)

if (!(Test-Path $ConfigurationFile)) {
	Write-Host "Configuration file '$($ConfigurationFile)' not found." -ForegroundColor Red
	Write-Host  "Please use 'set-installation...ps1' files to generate a configuration file." -ForegroundColor Red
	Exit 1
}
$config = Get-Content -Raw $ConfigurationFile | ConvertFrom-Json
if (!$config) {
	throw "Error trying to load configuration!"
}

$assets = $config.assets
$solrInstallConfigurationPath = Resolve-Path "assets\configuration\XP0\Solr-SingleDeveloper.json"

Import-Module (Join-Path $assets.sharedUtilitiesRoot "assets\modules\SharedInstallationUtilities\SharedInstallationUtilities.psm1") -Force


$params = @{
	SolrVersion       = $solrVersion
	SolrDomain        = "localhost"
	SolrPort          = $solrPort
	SolrServicePrefix = ""
	SolrInstallRoot   = $installFolder
}

Import-SitecoreInstallFramework -version $assets.installerVersion -repositoryName $assets.psRepositoryName -repositoryUrl $assets.psRepository
if ($Uninstall){
	Install-SitecoreConfiguration -Path $solrInstallConfigurationPath @params -Uninstall
}
else {
	Install-SitecoreConfiguration -Path $solrInstallConfigurationPath @params
}


Write-Host ''
Write-Host 'Done!' -ForegroundColor Green
