# Credit primarily to jermdavis for the original script

Param(
    [string]$solrVersion = "7.2.1",
    [string]$installFolder = "c:\solr",
    [string]$solrPort = "8721",
    [string]$solrHost = "localhost",
    [bool]$solrSSL = $TRUE,
    [string]$nssmVersion = "2.24",
	[string]$keystoreSecret = "secret",
	[string]$KeystoreFile = 'solr-ssl.keystore.jks',
	[string]$SolrDomain = 'localhost',
	[string]$maxJvmMem = '512m',
	[switch]$Clobber
)
# Turning off progress bar to (greatly) speed up installation
$Global:ProgressPreference = "SilentlyContinue"

$solrName = "solr-$solrVersion"
$solrRoot = "$installFolder\$solrName"
$nssmRoot = "$installFolder\nssm-$nssmVersion"
$solrPackage = "http://archive.apache.org/dist/lucene/solr/$solrVersion/$solrName.zip"
$nssmPackage = "http://nssm.cc/release/nssm-$nssmVersion.zip"

$downloadFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("..\assets") 
if (!(Test-Path $downloadFolder)){
	New-Item -ItemType Directory -Path $downloadFolder
}
## Verify elevated
## https://superuser.com/questions/749243/detect-if-powershell-is-running-as-administrator
$elevated = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
if(!($elevated))
{
    throw "In order to install services, please run this script elevated."
}

$JavaMinVersionRequired = "8.0.1510"
if (Get-Module("helper")) {
	Remove-Module "helper"
 }
 Import-Module "$PSScriptRoot\helper.psm1"  

$ErrorActionPreference = 'Stop'

# Ensure Java environment variable
try {
	$keytool = (Get-Command 'keytool.exe').Source
} catch {
	$keytool = Get-JavaKeytool -JavaMinVersionRequired $JavaMinVersionRequired
}

# download & extract the solr archive to the right folder
$solrZip = "$downloadFolder\$solrName.zip"
downloadAndUnzipIfRequired "Solr" $solrRoot $solrZip $solrPackage $installFolder

# download & extract the nssm archive to the right folder
$nssmZip = "$downloadFolder\nssm-$nssmVersion.zip"
downloadAndUnzipIfRequired "NSSM" $nssmRoot $nssmZip $nssmPackage $installFolder

### PARAM VALIDATION
if($keystoreSecret -ne 'secret') {
	Write-Error 'The keystore password must be "secret", because Solr apparently ignores the parameter'
}

if((Test-Path $KeystoreFile)) {
	if($Clobber) {
		Write-Host "Removing $KeystoreFile..."
		Remove-Item $KeystoreFile
	} else {
		$KeystorePath = Resolve-Path $KeystoreFile
		Write-Error "Keystore file $KeystorePath already existed. To regenerate it, pass -Clobber."
	}
}

$P12Path = [IO.Path]::ChangeExtension($KeystoreFile, 'p12')
if((Test-Path $P12Path)) {
	if($Clobber) {
		Write-Host "Removing $P12Path..."
		Remove-Item $P12Path
	} else {
		$P12Path = Resolve-Path $P12Path
		Write-Error "Keystore file $P12Path already existed. To regenerate it, pass -Clobber."
	}
}

### DOING STUFF

Write-Host ''
Write-Host 'Generating JKS keystore...'
& $keytool -genkeypair -alias solr-ssl -keyalg RSA -keysize 2048 -keypass $keystoreSecret -storepass $keystoreSecret -validity 9999 -keystore $KeystoreFile -ext SAN=DNS:$SolrDomain,IP:127.0.0.1 -dname "CN=$SolrDomain, OU=Organizational Unit, O=Organization, L=Location, ST=State, C=Country"

Write-Host ''
Write-Host 'Generating .p12 to import to Windows...'
& $keytool -importkeystore -srckeystore $KeystoreFile -destkeystore $P12Path -srcstoretype jks -deststoretype pkcs12 -srcstorepass $keystoreSecret -deststorepass $keystoreSecret

Write-Host ''
Write-Host 'Trusting generated SSL certificate...'
$secureStringKeystorePassword = ConvertTo-SecureString -String $keystoreSecret -Force -AsPlainText
$root = Import-PfxCertificate -FilePath $P12Path -Password $secureStringKeystorePassword -CertStoreLocation Cert:\LocalMachine\Root
Write-Host 'SSL certificate is now locally trusted. (added as root CA)'

if(-not $KeystoreFile.EndsWith('solr-ssl.keystore.jks')) {
	Write-Warning 'Your keystore file is not named "solr-ssl.keystore.jks"'
	Write-Warning 'Solr requires this exact name, so make sure to rename it before use.'
}

$KeystorePath = Resolve-Path $KeystoreFile
Copy-Item $KeystorePath -Destination "$solrRoot\server\etc\solr-ssl.keystore.jks" -Force
 # Update solr cfg to use keystore & right host name
 if(Test-Path -Path "$solrRoot\bin\solr.in.cmd.old")
 {
		 Write-Host "Resetting solr.in.cmd" -ForegroundColor Green
		 Remove-Item "$solrRoot\bin\solr.in.cmd"
		 Rename-Item -Path "$solrRoot\bin\solr.in.cmd.old" -NewName "$solrRoot\bin\solr.in.cmd"   
 }

	 Write-Host "Rewriting solr config"

	 $cfg = Get-Content "$solrRoot\bin\solr.in.cmd"
	 Rename-Item "$solrRoot\bin\solr.in.cmd" "$solrRoot\bin\solr.in.cmd.old"
	 $certStorePath = "etc/solr-ssl.keystore.jks"
	 $newCfg = $cfg | ForEach-Object { $_ -replace "REM set SOLR_SSL_KEY_STORE=etc/solr-ssl.keystore.jks", "set SOLR_SSL_KEY_STORE=$certStorePath" }
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_SSL_KEY_STORE_PASSWORD=secret", "set SOLR_SSL_KEY_STORE_PASSWORD=$keystoreSecret" }
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_SSL_TRUST_STORE=etc/solr-ssl.keystore.jks", "set SOLR_SSL_TRUST_STORE=$certStorePath" }
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_SSL_TRUST_STORE_PASSWORD=secret", "set SOLR_SSL_TRUST_STORE_PASSWORD=$keystoreSecret" }
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_HOST=192.168.1.1", "set SOLR_HOST=$solrHost" }
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_JAVA_MEM=-Xms512m -Xmx512m", "set SOLR_JAVA_MEM=-Xms512m -Xmx$maxJvmMem" }
	 $newCfg | Set-Content "$solrRoot\bin\solr.in.cmd"

# install the service & runs
$svc = Get-Service "$solrName" -ErrorAction SilentlyContinue
if(!($svc))
{
    Write-Host "Installing Solr service"
    &"$installFolder\nssm-$nssmVersion\win64\nssm.exe" install "$solrName" "$solrRoot\bin\solr.cmd" "-f" "-p $solrPort"
    $svc = Get-Service "$solrName" -ErrorAction SilentlyContinue
}

if($svc.Status -ne "Running")
{
	Write-Host "Starting Solr service..."
	Start-Service "$solrName"
}
elseif ($svc.Status -eq "Running")
{
	Write-Host "Restarting Solr service..."
	Restart-Service "$solrName"
}

        
Start-Sleep -s 5

# finally prove it's all working
$protocol = "http"
if($solrSSL)
{
    $protocol = "https"
}

Invoke-Expression "start $($protocol)://$($solrHost):$solrPort/solr/#/"

# Resetting Progress Bar back to default
$Global:ProgressPreference = "Continue"

Write-Host ''
Write-Host 'Done!' -ForegroundColor Green
