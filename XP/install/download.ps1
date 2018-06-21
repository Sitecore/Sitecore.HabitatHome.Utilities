Param(
    [string]$assetsFile = ".\assets.json",
    [string]$DownloadFolder = ".\downloads"
)

$assets = $(Get-Content $assetsFile -Raw | ConvertFrom-Json)

Function Invoke-FetchSitecoreCredentials {
    #   Credit: https://jermdavis.wordpress.com/2017/11/27/downloading-stuff-from-dev-sitecore-net/
    $file = "dev.creds.xml"
 
    if (Test-Path ".\\$file") {
        $cred = Import-Clixml ".\\$file"
    }
    else {
        $cred = Get-Credential -Message "Enter your SDN download credentials:"
        $cred | Export-Clixml ".\\$file"
    }
 
    return $cred
}

Function Invoke-FetchDownloadAuthentication($cred) {
    #   Credit: https://jermdavis.wordpress.com/2017/11/27/downloading-stuff-from-dev-sitecore-net/

    $authUrl = "https://dev.sitecore.net/api/authorization"
 
    $pwd = $cred.GetNetworkCredential().Password
 
    $postParams = "{ ""username"":""$($cred.UserName)"", ""password"":""$pwd"" }"
 
    $authResponse = Invoke-WebRequest -Uri $authUrl -Method Post -ContentType "application/json;charset=UTF-8" -Body $postParams -SessionVariable webSession
    $authCookies = $webSession.Cookies.GetCookies("https://sitecore.net")
 
    $marketPlaceCookie = $authCookies["marketplace_login"]
 
    if ([String]::IsNullOrWhiteSpace($marketPlaceCookie)) {
        throw "Credentials appear invalid"
    }
 
    $devUrl = "https://dev.sitecore.net"
 
    $devResponse = Invoke-WebRequest -Uri $devUrl -WebSession $webSession
    $devCookies = $webSession.Cookies.GetCookies("https://dev.sitecore.net")
 
    $sessionCookie = $devCookies["ASP.Net_SessionId"]
 
    return "$marketPlaceCookie; $sessionCookie"
}

function Invoke-SitecoreFileDownload {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Uri,
 
        [Parameter(Mandatory)]
        [string] $OutputFile,
 
        [string] $cookies
    )
    #   Credit: https://jermdavis.wordpress.com/2017/11/27/downloading-stuff-from-dev-sitecore-net/

    $webClient = New-Object System.Net.WebClient
 
    if (!([String]::IsNullOrWhiteSpace($cookies))) {
        $webClient.Headers.Add([System.Net.HttpRequestHeader]::Cookie, $cookie)
    }
 
    $data = New-Object psobject -Property @{Uri = $Uri; OutputFile = $OutputFile}
 
    $changed = Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -MessageData $data -Action {
        Write-Progress -Activity "Downloading $($event.MessageData.Uri)" -Status "To $($event.MessageData.OutputFile)" -PercentComplete $eventArgs.ProgressPercentage
    }
 
    try {
        $handle = $webClient.DownloadFileAsync($Uri, $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputFile))
 
        while ($webClient.IsBusy) {
            Start-Sleep -Milliseconds 1000
        }
    }
    finally {
        Write-Progress -Activity "Downloading $Uri" -Completed
 
        Remove-Job $changed -Force
        Get-EventSubscriber | Where SourceObject -eq $webClient | Unregister-Event -Force
    }    
}
Function Invoke-SitecoreDownload {
    param(
        [string]$url,
        [string]$target,
        [string]$source
    )
    if ($source -eq "sitecore") {
        $cred = Invoke-FetchSitecoreCredentials
        $cookie = Invoke-FetchDownloadAuthentication $cred
 
        Invoke-SitecoreFileDownload -Uri $url -OutputFile $target -Cookies $cookie
    }
    else {
        Invoke-SitecoreFileDownload -Uri $url -OutputFile $target 
    }
}
# Download Sitecore
if (!(Test-Path $DownloadFolder)){
    New-Item -ItemType Directory -Force -Path $DownloadFolder
}
foreach ($package in $assets.sitecore) {
    if ($package.download -eq $true) {
        Write-Host ("Downloading {0}  -  if required" -f $package.fileName )
        
        $destination = $([io.path]::combine((Resolve-Path $downloadFolder),  $package.fileName))
        Invoke-SitecoreDownload $package.url $destination $package.source
    }
}
foreach ($package in $assets.modules) {
    if ($package.download -eq $true) {
        Write-Host ("Downloading {0}  -  if required" -f $package.fileName )
        $destination = $([io.path]::combine((Resolve-Path $downloadFolder),  $package.fileName))
        Invoke-SitecoreDownload $package.url $destination $package.source
    }
}
foreach ($package in $assets.prerequisites) {
    if ($package.download -eq $true) {
        Write-Host ("Downloading {0}  -  if required" -f $package.fileName )
        $destination = $([io.path]::combine((Resolve-Path $downloadFolder),  $package.fileName))
        Invoke-SitecoreDownload $package.url $destination $package.source
    }
}
Write-Host "Installing WPI, Url Rewrite and Web Deploy 3.6"
$wpiDestination = $([io.path]::combine($downloadFolder, $webPIPackageFileName))
if (!(Test-Path $wpiDestination)) {
    Start-BitsTransfer -Source $webPIPackageUrl -Destination $wpiDestination
    Start-Process -FilePath "assets\WebPlatformInstaller_amd64_en-US.msi" -Wait
}
set-alias wpi "$env:ProgramFiles\Microsoft\Web Platform Installer\WebpiCmd-x64.exe"
wpi /install /Products:"UrlRewrite2"  /AcceptEULA
wpi /install /Products:"WDeploy36NoSMO"  /AcceptEULA


$resources = $json.resources
$resourcesName = "Sitecore.WDP.Resources"
$resourcesVersion = $resources.Replace($resourcesName + ".", "")

if ($useLocal -eq $false) {
    Write-Host ("Installing Resource Version '{0}'" -f $resourcesVersionJ)  -ForegroundColor Green
    nuget install $resourcesName -Version $resourcesVersion -Source $WdpResourcesFeed -OutputDirectory . -x -prerelease
}

New-Item -ItemType Directory -Force -Path $($downloadFolder + "\packages")

Write-Host "Downloading latest SPE and SXA`r`n" -ForegroundColor Green

$packagesFolder = (Join-Path $downloadFolder "packages")

if (!(Test-Path (Join-Path $packagesFolder $sxaPackageFileName))) {
    Start-BitsTransfer -Source $sxaPackageUrl -Destination (Join-Path $packagesFolder $sxaPackageFileName)
}
 
Write-Host "Downloading Data Exchange Framework related packages`r`n" -ForegroundColor Green
if (!(Test-Path (Join-Path $packagesFolder $spePackageFileName))) {
    Start-BitsTransfer -Source $spePackageUrl -Destination (Join-Path $packagesFolder $spePackageFileName)
}
if (!(Test-Path (Join-Path $packagesFolder $DEFPackageFileName))) {
    Start-BitsTransfer -Source $DEFPackageUrl -Destination (Join-Path $packagesFolder $DEFPackageFileName)
}
if (!(Test-Path (Join-Path $packagesFolder $DEFSitecoreProviderPackageFileName))) {
    Start-BitsTransfer -Source $DEFSitecoreProviderPackageUrl -Destination (Join-Path $packagesFolder $DEFSitecoreProviderPackageFileName)
}
if (!(Test-Path (Join-Path $packagesFolder $DEFxConnectProviderPackageFileName))) {
    Start-BitsTransfer -Source $DEFxConnectProviderPackageUrl -Destination (Join-Path $packagesFolder $DEFxConnectProviderPackageFileName)
}
if (!(Test-Path (Join-Path $packagesFolder $DEFDynamicsProviderPackageFileName))) {
    Start-BitsTransfer -Source $DEFDynamicsProviderPackageUrl -Destination (Join-Path $packagesFolder $DEFDynamicsProviderPackageFileName)
}
if (!(Test-Path (Join-Path $packagesFolder $DEFDynamicsConnectPackageFileName))) {
    Start-BitsTransfer -Source $DEFDynamicsConnectPackageUrl -Destination (Join-Path $packagesFolder $DEFDynamicsConnectPackageFileName)
}
if (!(Test-Path (Join-Path $packagesFolder $DEFSqlProviderPackageFileName))) {
    Start-BitsTransfer -Source $DEFSqlProviderPackageUrl -Destination (Join-Path $packagesFolder $DEFSqlProviderPackageFileName)
}

