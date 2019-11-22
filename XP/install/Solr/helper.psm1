Function Get-JavaVersions() {
    $versions = '', 'Wow6432Node\' |
        ForEach-Object {Get-ItemProperty -Path HKLM:\SOFTWARE\$($_)Microsoft\Windows\CurrentVersion\Uninstall\* |
            Where-Object {($_.DisplayName -like '*Java *') -and (-not $_.SystemComponent)} |
            Select-Object DisplayName, DisplayVersion, InstallLocation, @{n = 'Architecture'; e = {If ($_.PSParentPath -like '*Wow6432Node*') {'x86'} Else {'x64'}}}}
    
    return $versions
}
Function Get-JavaInstallationPath
{
    param (
        [version] $toVersion
    )
    $versions_ = Get-JavaVersions
    $foundRightVersion = $false
    $JavaInstallPath = ""
    foreach ($version_ in $versions_) {
        try {
            $version = New-Object System.Version($version_.DisplayVersion)
        }
        catch {
            continue
        }
        
        if ($version.CompareTo($toVersion) -ge 0) {
            $foundRightVersion = $true
            $JavaInstallPath = $version_.InstallLocation
            break;
        }
    }

    if (-not $foundRightVersion) {
        throw "Invalid Java version. Expected $JavaMinVersionRequired or above."
    }
    return $JavaInstallPath
}

Function Find-UpdateJAVAHOME
{
    param (
        [Version] $JavaMinVersionRequired
    )
    $JREPath = Get-JavaInstallationPath($JavaMinVersionRequired)
    
    $jreVal_ = [Environment]::GetEnvironmentVariable("JAVA_HOME", [EnvironmentVariableTarget]::Machine)
    if($jreVal_ -ne $JREPath)
    {
        Write-Host "Setting JAVA_HOME environment variable"
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $JREPath, [EnvironmentVariableTarget]::Machine)
        
        # Fixed known issue: error finding keytool
        $jreVal_ = $JREPath
    }

    return $jreVal_
}

Function Get-JavaKeytool
{
    param (
        [string] $JavaMinVersionRequired = "8.0.1510"
    )

    $RequiredVersion = New-Object System.Version($JavaMinVersionRequired)
    try {
        $jreVal = Find-UpdateJAVAHOME -JavaMinVersionRequired $RequiredVersion
        
        $path = $jreVal + '\bin\keytool.exe'
        
        if (Test-Path $path) {
            $keytool_ = (Get-Command $path).Source
        }
    } catch {
        $keytool_ = Read-Host "keytool.exe not on path. Enter path to keytool (found in JRE bin folder)"
    }

    if([string]::IsNullOrEmpty($keytool_) -or -not (Test-Path $keytool_)) {
        throw "Keytool path was invalid."
    }

    return $keytool_
}

function downloadAndUnzipIfRequired
{
    Param(
        [string]$toolName,
        [string]$toolFolder,
        [string]$toolZip,
        [string]$toolSourceFile,
        [string]$installRoot
    )

    if(!(Test-Path -Path $toolFolder))
    {
        if(!(Test-Path -Path $toolZip))
        {
            Write-Host "Downloading $toolName..."
            Start-BitsTransfer -Source $toolSourceFile -Destination $toolZip
        }

        Write-Host "Extracting $toolName to $toolFolder..."
        Expand-Archive $toolZip -DestinationPath $installRoot
    }
}