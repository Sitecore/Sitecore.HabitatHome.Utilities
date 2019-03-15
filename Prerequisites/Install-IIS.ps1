Set-ExecutionPolicy Bypass -Scope Process

# To list all Windows Features: dism /online /Get-Features
# Get-WindowsOptionalFeature -Online 

# LIST All IIS FEATURES: 
# Get-WindowsOptionalFeature -Online | where FeatureName -like 'IIS-*'
$features=@(
    "IIS-WebServerRole",
    "IIS-WebServer",
    "IIS-CommonHttpFeatures",
    "IIS-HttpErrors",
    "IIS-HttpRedirect",
    "IIS-ApplicationDevelopment",
    "NetFx4Extended-ASPNET45",
    "IIS-NetFxExtensibility45",
    "IIS-HealthAndDiagnostics",
    "IIS-HttpLogging",
    "IIS-LoggingLibraries",
    "IIS-RequestMonitor",
    "IIS-HttpTracing",
    "IIS-Security",
    "IIS-RequestFiltering",
    "IIS-Performance",
    "IIS-WebServerManagementTools",
    "IIS-IIS6ManagementCompatibility",
    "IIS-Metabase",
    "IIS-ManagementConsole",
    "IIS-BasicAuthentication",
    "IIS-WindowsAuthentication",
    "IIS-StaticContent",
    "IIS-DefaultDocument",
    "IIS-WebSockets",
    "IIS-ApplicationInit",
    "IIS-ISAPIExtensions",
    "IIS-ISAPIFilter",
    "IIS-HttpCompressionStatic",
    "IIS-ASPNET45"
)

foreach ($feature in $features) {
    Write-Host "=======Installing $feature========" -foreground Green
    Enable-WindowsOptionalFeature -Online -FeatureName $feature -Verbose
    Write-Host "=======Installed $feature========" -foreground Green
}

#REM The following optional components require 
#REM Chocolatey OR Web Platform Installer to install

#REM Install UrlRewrite Module for Extensionless Urls (optional)
#REM & "C:\Program Files\Microsoft\Web Platform Installer\WebpiCmd-x64.exe" /install /Products:UrlRewrite2 /AcceptEULA /SuppressPostFinish
Write-Host "=======Installing UrlRewrite========" -foreground Green
choco install urlrewrite -y
Write-Host "=======Installed UrlRewrite========" -foreground Green

#REM Install WebDeploy for Deploying to IIS (optional)
#REM & "C:\Program Files\Microsoft\Web Platform Installer\WebpiCmd-x64.exe" /install /Products:WDeployNoSMO /AcceptEULA /SuppressPostFinish

Write-Host "=======Installing WebDeploy========" -foreground Green
choco install webdeploy -y
Write-Host "=======Installed WebDeploy========" -foreground Green
