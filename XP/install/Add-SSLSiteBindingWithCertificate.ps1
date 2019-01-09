Param(
    [string] $ConfigurationFile = "configuration-xp0.json",
    [string] $SiteName,
    [string] $HostName,
    [string] $CertificateName,
    [int] $Port = 443,
    [switch] $SkipCreateCert,
    [switch] $SslOnly
)

#####################################################
# 
#  Install Sitecore
# 
#####################################################
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (!(Test-Path $ConfigurationFile)) {
    Write-Host "Configuration file '$($ConfigurationFile)' not found." -ForegroundColor Red
    Write-Host  "Please use 'set-installation...ps1' files to generate a configuration file." -ForegroundColor Red
    Exit 1
}
$config = Get-Content -Raw $ConfigurationFile |  ConvertFrom-Json
if (!$config) {
    throw "Error trying to load configuration!"
}


$site = $config.settings.site
$assets = $config.assets

function Install-Assets {
    Write-Host "Installing Assets"
    #Register Assets PowerShell Repository
    if ((Get-PSRepository | Where-Object {$_.Name -eq $assets.psRepositoryName}).count -eq 0) {
        Register-PSRepository -Name $assets.psRepositoryName -SourceLocation $assets.psRepository -InstallationPolicy Trusted
    }

    #Sitecore Install Framework dependencies
    Import-Module WebAdministration

    #Install SIF
    $module = Get-Module -FullyQualifiedName @{ModuleName = "SitecoreInstallFramework"; ModuleVersion = $assets.installerVersion}
    if (-not $module) {
        write-host "Installing the Sitecore Install Framework, version $($assets.installerVersion)" -ForegroundColor Green
        Install-Module SitecoreInstallFramework -RequiredVersion $assets.installerVersion -Repository $assets.psRepositoryName -Scope CurrentUser 
        Import-Module SitecoreInstallFramework -RequiredVersion $assets.installerVersion
    }

    #Verify that manual assets are present
    if (!(Test-Path $assets.root)) {
        throw "$($assets.root) not found"
    }
}
function Add-SSLSiteBindingWithCertificate {
    try {
        $params = @{
            Path            = $site.addSiteBindingWithSSLPath 
            SiteName        = $siteName 
            WebRoot         = $site.webRoot 
            HostHeader      = $HostName 
            Port            = $Port
            CertPath        = $assets.certificatesPath
            CertificateName = $CertificateName
            Skip            = @()
        }
        if ($SkipCreateCert) {
            $params.Skip += "CreatePaths", "CreateRootCert", "ImportRootCertificate", "CreateSignedCert"
        }
        if ($SslOnly) {
            $params.Skip += "CreateBindings"
        }
        Install-SitecoreConfiguration  @params   -WorkingDirectory $(Join-Path $PWD "logs") -Verbose
    }
    catch {
        write-host "Sitecore Setup Failed" -ForegroundColor Red
        throw
    }
}
    
Install-Assets
Add-SSLSiteBindingWithCertificate