Param(
    [string] $ConfigurationFile = "configuration-xc0.json",
    [string] $CertificateName,
    [string] $HostName
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

#$carbon = Get-Module Carbon
#if (-not $carbon) {
#    Write-Host "Installing latest version of Carbon" -ForegroundColor Green
#    Install-Module -Name Carbon -Repository PSGallery -AllowClobber -Verbose
#    Import-Module Carbon
#}

$engineSites = @("CommerceAuthoring_{0}:5000", "CommerceMinions_{0}:5010", "CommerceOps_{0}:5015", "CommerceShops_{0}:5005", "SitecoreBizFx:4200", "SitecoreIdentityServer:5050")

$site = $config.settings.site
$assets = $config.assets
$commerce = $config.settings.commerce
$resourcePath = Join-Path $assets.root "Resources"

function Install-Assets {
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
function Add-CommerceAdditionalBindings {
    # Get Thumbprint
    foreach ($engineSite in $engineSites) {
        $engineSite = ($engineSite -f $site.prefix)
        $siteName = $engineSite.Split(":")[0]
        $port = $engineSite.Split(":")[1]
        
        #Write-Host $sitename
        try {
            $params = @{
                Path       = $commerce.engineConfigurationPath 
                SSLCert    = $CertificateName 
                SiteName   = $siteName 
                HostHeader = $HostName 
                Port       = $port
            }

            Install-SitecoreConfiguration  @params  -WorkingDirectory $(Join-Path $PWD "logs") -Verbose         
        }
        catch {
            write-host "Sitecore Setup Failed" -ForegroundColor Red
            throw
        }
    }
}
Function Set-ModulesPath {
    Write-Host "Setting Modules Path" -ForegroundColor Green
    $modulesPath = ( Join-Path -Path $resourcePath -ChildPath "Modules" )
    if ($env:PSModulePath -notlike "*$modulesPath*") {
        $p = $env:PSModulePath + ";" + $modulesPath
        [Environment]::SetEnvironmentVariable("PSModulePath", $p)
    }
}

Set-ModulesPath
Install-Assets
Add-CommerceAdditionalBindings
