Param(
    [string] $ConfigurationFile = "configuration-xp0.json"
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

$carbon = Get-Module Carbon
if (-not $carbon) {
    Write-Host "Installing latest version of Carbon" -ForegroundColor Green
    Install-Module -Name Carbon -Repository PSGallery -AllowClobber -Verbose
    Import-Module Carbon
}

$engineSites = @("CommerceAuthoring_habtat:5000", "CommerceMinions_habtat:5010", "CommerceOps_habtat:5015", "CommerceShops_habtat:5005", "SitecoreBizFx:4200", "SitecoreIdentityServer:5050")

$site = $config.settings.site
$xConnect = $config.settings.xConnect
$assets = $config.assets

Import-Module .\scripts\additional-tasks.psm1 -Force

Write-Host "*******************************************************" -ForegroundColor Green
Write-Host " Installing Sitecore $($assets.sitecoreVersion)" -ForegroundColor Green
Write-Host " Sitecore: $($site.hostName)" -ForegroundColor Green
Write-Host " xConnect: $($xConnect.siteName)" -ForegroundColor Green
Write-Host "*******************************************************" -ForegroundColor Green


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
    foreach ($engineSite in $engineSites) {
        $siteName = $engineSite.Split(":")[0]
        $port = $engineSite.Split(":"[1])
    
        try {
            Install-SitecoreConfiguration $site.habitatHomeConfigurationPath `
                -SSLCert $site.habitatHomeSslCertificateName `
                -SiteName $siteName `
                -HostHeader "habitathome.dev.local" `
                -Port $port
        
        }
        catch {
            write-host "Sitecore Setup Failed" -ForegroundColor Red
            throw
        }
    }
}


Install-Assets
Add-CommerceAdditionalBindings
