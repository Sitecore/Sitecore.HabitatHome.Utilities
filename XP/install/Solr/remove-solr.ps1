Param(
    [string]$solrVersion = "7.5.0",
    [string]$installFolder = "c:\solr",
    [string]$nssmVersion = "2.24",
    [string]$keystoreSecret = "secret",
	[string]$KeystoreFile = 'solr-ssl.keystore.jks'
)


$solrName = "solr-$solrVersion"
$solrRoot = "$installFolder\$solrName"
$nssmRoot = "$installFolder\nssm-$nssmVersion"
$nssmPackage = "http://nssm.cc/release/nssm-$nssmVersion.zip"
$downloadFolder =(Resolve-Path "..\assets")

$JavaMinVersionRequired = "8.0.1510"

$ErrorActionPreference = 'Stop'

if (Get-Module("helper")) {
   Remove-Module "helper"
}
Import-Module "$PSScriptRoot\helper.psm1"  

# download & extract the nssm archive to the right folder
$nssmZip = "$downloadFolder\nssm-$nssmVersion.zip"
downloadAndUnzipIfRequired "NSSM" $nssmRoot $nssmZip $nssmPackage $installFolder

Write-Host "Removing Solr service: $($solrName)" -ForegroundColor Green
$svc = Get-Service "$solrName" -ErrorAction SilentlyContinue
if($svc)
{
    $nssmTool = "$nssmRoot\win64\nssm.exe"
    if ($svc.Status -eq "Running")
    {
        &"$nssmTool" stop "$solrName"
    }
    &"$nssmTool" remove "$solrName" confirm
}


if((Test-Path $KeystoreFile)) {
    Write-Host "Removing JKS file: $($KeystoreFile)" -ForegroundColor Green
    
    # Ensure Java environment variable
    try {
        $keytool = (Get-Command 'keytool.exe').Source
    } catch {
        $keytool = Get-JavaKeytool -JavaMinVersionRequired $JavaMinVersionRequired
    } 

    & $keytool -delete -alias "solr-ssl" -storetype JKS -keystore $KeystoreFile -storepass $keystoreSecret

    Remove-Item $KeystoreFile
    
    $P12Path = [IO.Path]::ChangeExtension($KeystoreFile, 'p12')
    Write-Host "Removing P12 file: $($P12Path)" -ForegroundColor Green
    if((Test-Path $P12Path)) {
        Remove-Item $P12Path
    }
}


Write-Host "Removing Solr root folder: $($solrRoot)" -ForegroundColor Green
If((Test-Path $solrRoot)) {
    Remove-Item -Path $solrRoot -Force -Recurse
} 

Write-Host "Removing Solr SSL Certificate" -ForegroundColor Green
Get-ChildItem -Path "Cert:\LocalMachine\Root" | Where-Object -Property FriendlyName -eq "solr-ssl" | Remove-Item