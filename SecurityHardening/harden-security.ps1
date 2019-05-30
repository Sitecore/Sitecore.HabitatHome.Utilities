Param(
    [string]$siteName = "habitathome.dev.local",
    [string]$webRoot = "C:\inetpub\wwwroot"
)
## Executes security hardening base on doc.sitecore.com recommendations
## For more details, visit the Security Guide: https://doc.sitecore.com/developers/91/platform-administration-and-architecture/en/security-guide.html

$configurationPath = Resolve-Path .\configuration
$assetsPath = Resolve-Path .\assets

$sharedModulesPath = Resolve-Path ..\Shared\assets\modules

Import-Module SitecoreInstallFramework -RequiredVersion 2.1.0
Import-Module (Join-Path $sharedModulesPath 'SecurityHardening') -Force -Verbose

# Folders that will have the "Anonymous Authentication" feature disabled in IIS
# ref: https://doc.sitecore.com/developers/90/platform-administration-and-architecture/en/deny-anonymous-users-access-to-a-folder.html
$foldersToDenyAnonymousAccess = @('App_Config', 'sitecore/admin', 'sitecore/debug', 'sitecore/login', 'sitecore/shell/WebService')

#contains the list of files to .disable
# ref: https://doc.sitecore.com/developers/90/platform-administration-and-architecture/en/disable-administrative-tools.html
$IOActionPath = Join-Path $assetsPath "ioactions.xml" 

$uploadFilterPackageUri = "http://doc.sitecore.com/resources/upload-filter-1.0.0.2.zip"

$workingFolder = Join-Path $assetsPath "work"

if (!(Test-Path $workingFolder)) {
    New-Item -Path $workingFolder -ItemType Directory -Force
}

$uploadFilterPackageFileName = "upload-filter-1.0.0.2.zip"

$params = @{
    WebRoot                     = $webRoot
    SiteName                    = $siteName
    FoldersToDisable            = $foldersToDenyAnonymousAccess   
    IOActionPath                = $IOActionPath
    UploadFilterPackageUri      = $uploadFilterPackageUri
    UploadFilterPackageFileName = $uploadFilterPackageFileName
    WorkingFolder               = $workingFolder
    ConfigurationPatchPath      = Resolve-Path .\assets\configs
    TransformSourcePath         = Resolve-Path .\assets\transforms
}


Push-Location $configurationPath
Install-SitecoreConfiguration -Path .\harden-security.json @params -Verbose 
Pop-Location