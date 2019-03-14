function InstallNugetPackageProvider{
    Write-Host "===========================Install-PackageProvider===========================" -foreground Green
    #PowerShellGet requires NuGet provider version '2.8.5.201' or newer to interact with NuGet-based repositories.
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}

function InstallOrUpdateChocoPackages {
    $packages = @(
        #Format: (id, version)
        ('googlechrome', ''), 
        ('git', ''),
        ('NuGet.CommandLine', ''),
        ('7zip', ''),
        ('nodejs.install', ''),
        ('vscode', ''),
        ('vscode-powershell', ''),
        ('vscode-csharp', ''),
        ('jre8', ''),
        #('urlrewrite', ''), #installed inside '\Install-IIS.ps1'
        ('snaketail', '')
    )

    $installedPackages = choco list -lo
    foreach ($package in $packages) {
        $installedPackage = $installedPackages | Where-object { $_.ToLower().StartsWith($package[0].ToLower() + ' ') }
        $installedVersion = ''
        if (![string]::IsNullOrEmpty($installedPackage)) {
            $installedVersion = $installedPackage.Split(' ')[1]
        }
        Write-Host "InstallOrUpdateChocoPackage -packageId $package[0] -version $package[1] -installedVersion $installedVersion" 
        InstallOrUpdateChocoPackage -packageId $package[0] -version $package[1] -installedVersion $installedVersion
    }
}

<#
    InstallOrUpdateChocoPackage
#>
function InstallOrUpdateChocoPackage {
    param (
        [string]$packageId,
        [string]$version,
        [string]$installedVersion
    )

    if ([string]::IsNullOrEmpty($installedVersion)) {
        #if no version is installed
        if ([string]::IsNullOrEmpty($version)) {
            #if not require specified version, intall latest version
            choco install $packageId -y --accept-license -Verbose
        }
        else {
            #install specified version
            choco install $packageId -version $version -y --accept-license -Verbose
        }
        return
    }
    #if already installed a version, check update
    if ([string]::IsNullOrEmpty($version)) {
        #if not require specified version, upgrade to latest
        choco upgrade $packageId -y --accept-license -Verbose
        return
    }
    #if a version installed, and required version is specified

    if ($version -lt $installedVersion) {
        #if need a older version
        Write-Host "the required version of module $packageId is $version, but a newer version $installedVersion is already installed." -foreground Yellow
        return
        
    }
    elseif ($version -gt $installedVersion) {
        #if need a new version
        choco upgrade $packageId -version $version -y --accept-license -Verbose
        return
    }
    else {
        # do nothing if already same version
    }
}

InstallNugetPackageProvider
InstallOrUpdateChocoPackages