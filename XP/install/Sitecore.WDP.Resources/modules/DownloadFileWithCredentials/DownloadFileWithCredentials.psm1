Function Invoke-DownloadFileWithCredentialsTask {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceUri,
        [Parameter(Mandatory = $true)]
        [ValidateScript( { Test-Path -Path (Split-Path -Path $_ -Parent) })]
        [ValidateScript( { Test-Path -Path $_ -PathType Leaf -IsValid })]
        [string]$DestinationPath,
        [PSCredential]$Credentials,
        [switch] $ProgressBar
    )

    if ($PSCmdlet.ShouldProcess($SourceUri, "Download $SourceUri to $DestinationPath")) {

        try {
            Write-Verbose "Downloading $SourceUri to $DestinationPath"
            $ProgressPreference = 'SilentlyContinue'

            if ($ProgressBar) {
                $ProgressPreference = 'Continue'
            }
            if ($Credentials) {
                
                $user = $Credentials.GetNetworkCredential().username
                
                $password = $Credentials.GetNetworkCredential().password
                $loginRequest = Invoke-RestMethod -Uri https://dev.sitecore.net/api/authorization -Method Post -ContentType "application/json" -Body "{username: '$user', password: '$password'}" -SessionVariable session -UseBasicParsing
                
                Invoke-WebRequest -Uri $SourceUri -OutFile $DestinationPath -WebSession $session -UseBasicParsing
            }
            else {
                Write-Verbose "here"
                Invoke-WebRequest -Uri $SourceUri -OutFile $DestinationPath -UseBasicParsing
            }
            $ProgressPreference = 'Continue'

        }
        catch {
            Write-Error -Message ("Error downloading $SourceUri" + ": $($_.Exception.Message)")
        }
    }
}

Register-SitecoreInstallExtension -Command Invoke-DownloadFileWithCredentialsTask -As DownloadFileWithCredentials -Type Task -Force