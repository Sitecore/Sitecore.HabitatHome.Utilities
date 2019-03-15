$Global:ProgressPreference = 'SilentlyContinue'
Install-SitecoreConfiguration -Path (Resolve-Path .\prerequisites.json)
$Global:ProgressPreference = 'Continue'