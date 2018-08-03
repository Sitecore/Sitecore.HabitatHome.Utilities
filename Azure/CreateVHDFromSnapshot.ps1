Param(
    [string] $subscriptionId,
    [string] $snapshotPrefix = "habitathome",
    [ValidateSet('xp', 'xc')]
    [string]$demoType,
    [string[]] $regions = @("na", "emea", "ga", "ea")


)
$config = Get-Content .\config.json | ConvertFrom-Json

$account = Get-AzureRMContext | Select-Object Account

if ($account.Account -eq $null) {
    Login-AzureRmAccount
}

### DO NOT CHANGE
$demoType = $demoType.ToLower()
$snapshotResourceGroupName = ("{0}-demo-snapshot" -f $snapshotPrefix)
$osSnapshotName = ("{0}{1}-os-snapshot" -f $snapshotPrefix, $demoType)
Write-host ("Preparing to copy {0} from {1}" -f $osSnapshotName, $snapshotResourceGroupName)
#Provide the name of the VHD file to which snapshot will be copied.
$osVHDFileName = ("{0}{1}-os.vhd" -f $snapshotPrefix, $demoType)


$sasExpiryDuration = "10800"

Select-AzureRmSubscription -SubscriptionId $subscriptionId

#     Write-Host "Generating SAS tokens for snapshot(s)..." -ForegroundColor Green

$DebugPreference = 'Continue'
$result = Grant-AzureRmSnapshotAccess -ResourceGroupName $snapshotResourceGroupName -SnapshotName $osSnapshotName -Access 'Read' -DurationInSecond $sasExpiryDuration 5>&1

$DebugPreference = 'SilentlyContinue'

$sasUri = ((($result | Where-Object {$_ -match "accessSAS"})[-1].ToString().Split("`n") | Where-Object {$_ -match "accessSAS"}).Split(' ') | Where-Object {$_ -match "https"}).Replace('"', '')

if (Test-Path (Join-Path $PWD "vhdcreation.log") -PathType Leaf) {
    Remove-Item (Join-Path $PWD "vhdcreation.log") -Force
}


$Block = {
    param(
        [string]$region,
        $sas,
        $config,
        $osVHDFileName
    )

    $configRegion = ($config.regions | Where-Object {$_.name -eq $region})

    $storageAccountName = $configRegion.StorageAccountName
    $keys = Get-AzureRmStorageAccountKey -ResourceGroupName $configRegion.resourceGroupName -Name $configRegion.StorageAccountName
    $storageAccountKey = $keys[0].Value
    $storageContainerName = $configRegion.StorageContainerName

    #Create the context for the storage account which will be used to copy snapshot to the storage account 
    $destinationContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

    Write-Host "Copying OS Disk" -ForegroundColor Green
    $progress = Start-AzureStorageBlobCopy -AbsoluteUri $sas -DestContainer $storageContainerName -DestContext $destinationContext -DestBlob $osVHDFileName -Force

    while (($progress | Get-AzureStorageBlobCopyState).Status -eq "Pending") {
        Start-Sleep -s 60
        $progress | Get-AzureStorageBlobCopyState
    }

    $result = ($progress | Get-AzureStorageBlobCopyState)

    if ($result.Status -eq "Success") {
        Write-Host ("Successful copy of OS Disk to {0}" -f $configRegion.location) -ForegroundColor Green
    }
    else {
        $message = ("Error copying OS disk to region {0}" -f $configRegion.location)
        Write-Host $message -ForegroundColor Red
        Add-Content -Path (Join-Path $PWD "vhdcreation.log") -Value $message -Force
    }

}

foreach ($region in $regions){
    $jobName = $region

    Start-Job -Name $jobName -ScriptBlock $Block -ArgumentList $region, $sasUri, $config, $osVHDFileName

}

while (1 -eq 1){


    $jobs = Get-Job | Where-Object {$_.State -eq "Running"}
    if ($jobs.Count -eq 0) {
        if (Test-Path $(Join-Path $PWD "vhdcreation.log")){
            # this means we've encountered an error
            Write-Host "Error copying VHD"
            break
        }
        else {
            Write-Host "Success!" -ForegroundColor Green
            break
        }
        return
    }
    foreach ($job in $jobs){
        Write-Host ("... Copy of VHD to {0} in progress" -f $job.Name)
        $jobs | Receive-Job
    }

    Start-Sleep -Seconds 120
}