Param(
    [string] $ConfigurationFile = "configuration-xp0.json",
    [string] $AssetsFile = "assets.json"
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
$sql = $config.settings.sql
$sitecore = $config.settings.sitecore
$assets = $config.assets
$modules = $config.modules
$resourcePath = Join-Path $PSScriptRoot "Sitecore.WDP.Resources"

Write-Host "*******************************************************" -ForegroundColor Green
Write-Host " Installing Optional Sitecore Modules $($assets.sitecoreVersion)" -ForegroundColor Green
Write-Host " Sitecore: $($site.hostName)" -ForegroundColor Green
Write-Host "*******************************************************" -ForegroundColor Green

function Confirm-Prerequisites {
    # Verify Web Deploy
    $webDeployPath = ([IO.Path]::Combine($env:ProgramFiles, 'iis', 'Microsoft Web Deploy V3', 'msdeploy.exe'))
    if (!(Test-Path $webDeployPath)) {
        throw "Could not find WebDeploy in $webDeployPath"
    }   

    #Verify that assets are present
    if (!(Test-Path $assets.root)) {
        throw "$($assets.root) not found"
    }

    #Verify license file
    if (!(Test-Path $assets.licenseFilePath)) {
        throw "License file $($assets.licenseFilePath) not found"
    }
    
    #Verify Sitecore package
    if (!(Test-Path $sitecore.packagePath)) {
        throw "Sitecore package $($sitecore.packagePath) not found"
    }
    
}
function Install-Assets {
    #Register Assets PowerShell Repository
    if ((Get-PSRepository | Where-Object {$_.Name -eq $assets.psRepositoryName}).count -eq 0) {
        Register-PSRepository -Name $assets.psRepositoryName -SourceLocation $assets.psRepository -InstallationPolicy Trusted 
    }

    #Sitecore Install Framework dependencies
    Import-Module WebAdministration
    #Install SIF
    $SIFVersion = $($assets.installerVersion -replace "-beta[0-9]*$")
    Write-Host ("Loading Sitecore Installer Framework {0}" -f $SIFVersion) -ForegroundColor Green

    $module = Get-Module -FullyQualifiedName @{ModuleName = "SitecoreInstallFramework"; ModuleVersion = $SIFVersion}
    


    if (-not $module) {
        write-host "Installing the Sitecore Install Framework, version $($assets.installerVersion)" -ForegroundColor Green
        if ($assets.installerversion -like "*beta*") {
            Install-Module SitecoreInstallFramework -RequiredVersion $assets.installerVersion -Repository $assets.psRepositoryName -Scope CurrentUser -Force -AllowPrerelease
        }
        else {
            Install-Module SitecoreInstallFramework -RequiredVersion $assets.installerVersion -Repository $assets.psRepositoryName -Scope CurrentUser -Force 
        }
        
        Import-Module SitecoreInstallFramework -RequiredVersion $SIFVersion -Force
    }
}



function Enable-InstallationImprovements {
    try {
        $params = @{
            Path        = $site.enableInstallationImprovements 
            InstallDir  = $sitecore.siteRoot  
            ResourceDir = $($assets.root + "\\Sitecore.WDP.Resources")
        }

        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs")
    }
    catch {
        write-host "$site.habitatHomeHostName Failed to enable installation improvements" -ForegroundColor Red
        throw
    }
}

function Disable-InstallationImprovements {
    try {
        $params = @{
            Path        = $site.disableInstallationImprovements 
            InstallDir  = $sitecore.siteRoot 
            ResourceDir = $($assets.root + "\\Sitecore.WDP.Resources")
        }
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs")
    }
    catch {
        write-host "$site.habitatHomeHostName Failed to disable installation improvements" -ForegroundColor Red
        throw
    }
}



Function Install-SitecorePowerShellExtensions {
    $spe = $modules | Where-Object { $_.id -eq "spe"}
    $spe.packagePath = $spe.packagePath.replace(".zip", ".scwdp.zip")
    $params = @{
        Path = (Join-path $resourcePath 'content\Deployment\OnPrem\HabitatHome\sitecore-spe.json')
        Package                             = $spe.packagePath
        SiteName                            = $site.hostName
        SqlDbPrefix                          = $site.prefix 
        SqlAdminUser                         = $sql.adminUser 
        SqlAdminPassword                     = $sql.adminPassword 
        SqlServer                            = $sql.server 

    }
    Write-Host @params
    Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") -Verbose
}

Function Install-SitecoreExperienceAccelerator {
    $sxa = $modules | Where-Object { $_.id -eq "sxa"}
    $sxa.packagePath = $sxa.packagePath.replace(".zip", ".scwdp.zip")
    $params = @{
        Path = (Join-path $resourcePath 'content\Deployment\OnPrem\HabitatHome\sitecore-sxa.json')
        Package                             = $sxa.packagePath
        SiteName                            = $site.hostName
        SqlDbPrefix                          = $site.prefix 
        SqlAdminUser                         = $sql.adminUser 
        SqlAdminPassword                     = $sql.adminPassword 
        SqlServer                            = $sql.server 

    }
    Write-Host @params
    Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs") -Verbose
    # Update SXA Solr Cores
    try {
        $params = @{
            Path        = $site.configureSearchIndexes 
            InstallDir  = $sitecore.siteRoot 
            ResourceDir = $($assets.root + "\\Sitecore.WDP.Resources")
            SitePrefix  = $site.prefix
        }
        Install-SitecoreConfiguration @params -WorkingDirectory $(Join-Path $PWD "logs")
    }
    catch {
        write-host "$site.habitatHomeHostName Failed to updated search index configuration" -ForegroundColor Red
        throw
    }
}

#Set-ModulesPath
Install-Assets
Confirm-Prerequisites
Install-SitecorePowerShellExtensions
Install-SitecoreExperienceAccelerator
#Disable-InstallationImprovementss