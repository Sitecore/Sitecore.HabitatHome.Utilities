function Install-Prerequisites {
    $tasks=$(
        '.\Install-Chocolatey.ps1',
        '.\Install-IIS.ps1',
        '.\Install-ChocoPackages.ps1',
        '.\Install-SitecoreGallery.ps1',
        '.\Install-SIF.ps1',
        '.\Install-SitecorePrerequisites.ps1'
    )
    foreach($task in $tasks){
        Write-Host "=========================[START]$task=============================" -foreground Green
        Invoke-Expression $task
        Write-Host "=========================[DONE]$task==============================" -foreground Green
    }
}

$Global:ProgressPreference = 'SilentlyContinue'
Install-Prerequisites
$Global:ProgressPreference = 'Continue'