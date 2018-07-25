Param(
    [string]$assetsFile = ".\assets.json",
    [string]$DownloadFolder = ".\assets",
    [string]$user,
    [string]$password
)

$assets = $(Get-Content $assetsFile -Raw | ConvertFrom-Json)
$packagesFolder = (Join-Path $downloadFolder "packages")
Set-Alias sz 'C:\Program Files\7-Zip\7z.exe'


Function Invoke-SitecoreDownload {
    param(
        [string]$url,
        [string]$target,
        [string]$source,
        [string]$user,
        [string]$password
    )
    if ($source -eq "sitecore") {
        $loginRequest = Invoke-RestMethod -Uri https://dev.sitecore.net/api/authorization -Method Post -ContentType "application/json" -Body "{username: '$user', password: '$password'}" -SessionVariable session -UseBasicParsing
        Invoke-WebRequest -Uri $url -WebSession $session -OutFile $target -UseBasicParsing
    }
    else {
        Write-Host ("Downloading {0}" -f $url)
        Invoke-WebRequest -Uri $url -WebSession $session -OutFile $target -UseBasicParsing
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
		if (!(Test-Path $destination)){
			Invoke-SitecoreDownload $package.url $destination $package.source $user $password
		}
		if ($package.extract -eq $true){
			sz x -o"$DownloadFolder" $destination -r -y -aoa
		}
    }
}
foreach ($package in $assets.modules) {
	
if (!(Test-Path $packagesFolder)){
    New-Item -ItemType Directory -Force -Path $packagesFolder
}
    if ($package.download -eq $true) {
        Write-Host ("Downloading {0}  -  if required" -f $package.fileName )
        $destination = $([io.path]::combine((Resolve-Path $packagesFolder),  $package.fileName))
		if (!(Test-Path $destination)){
			Invoke-SitecoreDownload $package.url $destination $package.source $user $password
		}
    }
}
foreach ($package in $assets.prerequisites) {
    if ($package.download -eq $true) {
        Write-Host ("Downloading {0}  -  if required" -f $package.fileName )
        $destination = $([io.path]::combine((Resolve-Path $downloadFolder),  $package.fileName))
		if (!(Test-Path $destination)){
			Invoke-SitecoreDownload $package.url $destination $package.source $user $password
		}
    }
}


