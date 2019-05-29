
Function Disable-AnonymousAccess {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$folders,
        [Parameter(Mandatory = $true)]
        [string]$siteName

    )
    Enable-WindowsFeatureDelegation -featureName "anonymousAuthentication"

    foreach ($folder in $folders) {
        Write-Verbose "Disabling anonymous access to $folder"
        Set-WebConfigurationProperty -Filter "/system.webServer/security/authentication/anonymousAuthentication" -Name Enabled -Value False -PSPath "IIS:\Sites\$siteName\$folder"
    }
    Write-Verbose -Message $PSCmdlet.MyInvocation.MyCommand

    # Disable-WindowsFeatureDelegation -featureName "anonymousAuthentication"
}

Function Enable-WindowsFeatureDelegation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$featureName
    )
    $delegateSet = (Get-WebConfiguration "/System.WebServer/Security/Authentication/$featureName" -PSPath IIS:/).OverrideMode
    if ($delegateSet -eq 'Deny' -or $delegateSet -eq 'Inherit' ) {
        Set-WebConfiguration "/System.WebServer/Security/Authentication/$featureName" -metadata overrideMode -value Allow -PSPath IIS:/
        Write-Output "Feature Delegation for $featureName has been set to Allow"
    }
}

Function Disable-WindowsFeatureDelegation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$featureName
    )
    $delegateSet = (Get-WebConfiguration "/System.WebServer/Security/Authentication/$featureName" -PSPath IIS:/).OverrideMode
    if ($delegateSet -eq 'Allow') {
        Set-WebConfiguration "/System.WebServer/Security/Authentication/$featureName" -metadata overrideMode -value Inherit -PSPath IIS:/
        Write-Output "Feature Delegation for $featureName has been set to Inherit"
    }
}

function Block-FilesUsingIOActions {
    param(
        [Parameter(Mandatory = $true, helpmessage = "Root Directory Path")]
        [string]$RootDirectoryPath,
        [Parameter(Mandatory = $true, helpmessage = "IO XML Document")]
        [string]$IoXmlPath
    )

    Write-Verbose "Entering Block-Files"
    
    $ioXml = (Get-Content $IoXmlPath) -as [xml]
    if ($ioXml -eq $null) {
        throw "'$IoXmlPath' is not a valid xml"
    }
    elseif ($ioXml.SelectNodes("IOActions/IOAction").Count -eq 0) {
        throw "'$IoXmlPath' is not a valid ioxml and does not contain required root elements"
    }

    Write-Verbose "$(@($ioXml.IOActions.IOAction).Count) IO Action(s) detected."

    $ioXml.IOActions.IOAction | ForEach-Object {
        $ioAction = $_
        switch ($ioAction.action) {
            "enable" {
                
                if (Test-Path (Join-Path $RootDirectoryPath $ioAction.path)) {
                    Rename-Item (Join-Path $RootDirectoryPath $ioAction.path) ((Join-Path $RootDirectoryPath $ioAction.path) -replace ".disabled", "")
                }
                else {
                    Write-Warning -Message "Cannot find the path '$($ioAction.path)'."
                }
                
            }
            "disable" {
                
                if (Test-Path (Join-Path $RootDirectoryPath $ioAction.path)) {
                    Rename-Item (Join-Path $RootDirectoryPath $ioAction.path) (Join-Path $RootDirectoryPath "$($ioAction.path).disabled")
                }
                else {
                    Write-Warning -Message "Cannot find the path '$($ioAction.path)'."
                }
                
            }
            "delete" {
                
                if (Test-Path (Join-Path $RootDirectoryPath $ioAction.path)) {
                    Remove-Item (Join-Path $RootDirectoryPath $ioAction.path) -Force
                }
                else {
                    Write-Warning -Message "Cannot find the path '$($ioAction.path)'."
                }
                
            }
            default {
                Write-Error -Message "$($ioAction.action) is not a valid action and has been ignored."
            }
        }
    }
}
