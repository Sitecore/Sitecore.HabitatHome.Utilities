
Param(
    $DownloadFolder = "",
    $CommerceAssetFolder = "",
    $CommercePackageUrl = "https://v9assets.blob.core.windows.net/v9-onprem-assets/Sitecore.Commerce.2018.03-2.1.55.zip?sv=2017-04-17&ss=bfqt&srt=sco&sp=rwdlacup&se=2027-11-09T20%3A11%3A50Z&st=2017-11-09T12%3A11%3A50Z&spr=https&sig=naspk%2BQflDLjyuC6gfXw4OZKvhhxzTlTvDctfw%2FByj8%3D"

)
if ($DownloadFolder -eq "") {
    $DownloadFolder = Join-Path "$PWD" "assets\Downloads"
}
if ($CommerceAssetFolder -eq "") {
    $CommerceAssetFolder = Join-Path "$PWD" "assets\Commerce"
}
$msbuildNuGetUrl = "https://v9assets.blob.core.windows.net/shared-assets/msbuild.microsoft.visualstudio.web.targets.14.0.0.3.nupkg"
$msbuildNuGetPackageFileName = "msbuild.microsoft.visualstudio.web.targets.14.0.0.3.nupkg"
$msbuildNuGetPackageDestination = $([io.path]::combine($DownloadFolder, $msbuildNuGetPackageFileName))

Write-Host "Saving $msbuildNuGetUrl to $msbuildNuGetPackageDestination - if required" -ForegroundColor Green
if (!(Test-Path $msbuildNuGetPackageDestination)) {
    Start-BitsTransfer -source $msbuildNuGetUrl -Destination $msbuildNuGetPackageDestination
}


$aspnetCoreGetUrl = "https://aka.ms/dotnetcore-2-windowshosting"
$aspnetCoreFileName = "DotNetCore.2.0.5-WindowsHosting.exe"
$aspnetPackageDestination = $([io.path]::combine($DownloadFolder, $aspnetCoreFileName))

Write-Host "Saving $aspnetCoreGetUrl to $aspnetPackageDestination - if required" -ForegroundColor Green
if (!(Test-Path $aspnetPackageDestination)) {
    Start-BitsTransfer -source $aspnetCoreGetUrl -Destination $aspnetPackageDestination
}

$netCoreSDKUrl = "https://download.microsoft.com/download/0/F/D/0FD852A4-7EA1-4E2A-983A-0484AC19B92C/dotnet-sdk-2.0.0-win-x64.exe"
$netCoreSDKFileName = "dotnet-sdk-2.0.0-win-x64.exe"
$netCoreSDKPackageDestination = $([io.path]::combine($DownloadFolder, $netCoreSDKFileName))

Write-Host "Saving $netCoreSDKUrl to $netCoreSDKPackageDestination - if required" -ForegroundColor Green
if (!(Test-Path $netCoreSDKPackageDestination)) {
    Start-BitsTransfer -source $netCoreSDKUrl -Destination $netCoreSDKPackageDestination
}


$commercePackagePaths = $CommercePackageUrl.Split("?")
$commercePackageFileName = $commercePackagePaths[0].substring($commercePackagePaths[0].LastIndexOf("/") + 1)
$commercePackageDestination = $([io.path]::combine($DownloadFolder, $commercePackageFileName)).ToString()

Write-Host "Saving $CommercePackageUrl to $commercePackageDestination - if required" -ForegroundColor Green
if (!(Test-Path $commercePackageDestination)) {
    Start-BitsTransfer -Source $CommercePackageUrl -Destination $commercePackageDestination
}

Write-Host "Extracting to $($CommerceAssetFolder)"
set-alias sz "$env:ProgramFiles\7-zip\7z.exe"
sz x -o"$CommerceAssetFolder" $commercePackageDestination -r -y -aoa

$habitatHomeImagePackageUrl = "https://v9assets.blob.core.windows.net/v9-onprem-assets/Habitat Home Product Images.zip?sv=2017-04-17&ss=bfqt&srt=sco&sp=rwdlacup&se=2027-11-09T20%3A11%3A50Z&st=2017-11-09T12%3A11%3A50Z&spr=https&sig=naspk%2BQflDLjyuC6gfXw4OZKvhhxzTlTvDctfw%2FByj8%3D"
$habitatHomeImagePackageFileName = "Habitat Home Product Images.zip"
$habitatHomeImagePackageDestination = (Join-Path $CommerceAssetFolder $habitatHomeImagePackageFileName)


if (!(Test-Path $habitatHomeImagePackageDestination)) {
    Write-Host ("Saving '{0}' to '{1}'" -f $habitatHomeImagePackageFileName, $CommerceAssetFolder) -ForegroundColor Green
    Start-BitsTransfer -source $habitatHomeImagePackageUrl -Destination $habitatHomeImagePackageDestination
}