param (
    [string]$moduleName,
    [string]$version
)

$module = Get-Module -ListAvailable $moduleName -Verbose

if (!$module) {
    # if not installed yet
    if ($version) {
        Install-Module $moduleName -RequiredVersion $version -Force -Verbose
    }
    else {
        Install-Module $moduleName -Force -Verbose
    }
    return
}
    
if ($module.Length -gt 1) {
    # if multiple versions are installed
    if (!$version) {
        Update-Module -Name $moduleName -Force -Verbose
        return
    }

    $isInstalled = $module|Where-Object {$_.Version -eq $version}

    if ($isInstalled) {
        Write-Host "the required version $version of module $moduleName is already installed" -foreground Yellow
    }
    else {
        Write-Host "Adding a new version $version to module $moduleName" -foreground Yellow
        Update-Module $moduleName -RequiredVersion $version -Force -Verbose
    }
    return
}

#process if only 1 version is installed
$installedVersion = $module.Version;
Remove-Module -ModuleInfo $module -Force -Verbose #unload module from current session

if ($installedVersion -ne $version) {
 
    if (!$version) {
        Update-Module -Name $moduleName -Force -Verbose
    }
    else {
        if ($installedVersion -gt $version) {
            Write-Host "the required version of module $moduleName is $version, but a newer version $installedVersion is already installed." -foreground Yellow
        }
        Update-Module $moduleName -RequiredVersion $version -Force -Verbose
    }
}
else {
    Write-Host "the required version $version of module $moduleName is already installed" -foreground Yellow
}

