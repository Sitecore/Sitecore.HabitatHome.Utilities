Param(
    [string] $subscriptionId
    
)
$config = Get-Content .\config.json | ConvertFrom-Json

$account = Get-AzureRMContext | Select-Object Account

if ($account.Account -eq $null) {
    Login-AzureRmAccount
}

### DO NOT CHANGE
$deploymentName = "habitathome"
$snapshotResourceGroupName = ("{0}-demo-snapshot" -f $deploymentName)
$osSnapshotName = ("{0}-os-snapshot" -f $deploymentName)
$dataSnapshotName = ("{0}-data-snapshot" -f $deploymentName)

#Provide the name of the VHD file to which snapshot will be copied.
$osVHDFileName = ("{0}-os.vhd" -f $deploymentName)
$dataVHDFileName = ("{0}-data.vhd" -f $deploymentName)


$sasExpiryDuration = "10800"

Select-AzureRmSubscription -SubscriptionId $subscriptionId

Write-Host "Generating SAS tokens for snapshot(s)..." -ForegroundColor Green


foreach ($region in $config.regions) {

    Write-Host ("Creating VHDs in {0}" -f $region.location) -ForegroundColor Green
    
    $storageAccountName = $region.StorageAccountName
    $keys = Get-AzureRmStorageAccountKey -ResourceGroupName $region.resourceGroupName -Name $region.StorageAccountName
    $storageAccountKey = $keys[0].Value
    $storageContainerName = $region.StorageContainerName

    #Create the context for the storage account which will be used to copy snapshot to the storage account 
    $destinationContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

    Write-Host "Copying VHDs - this will take a while... " -ForegroundColor Green
    Write-Host "Copying OS Disk" -ForegroundColor Green

    $osSAS = Grant-AzureRmSnapshotAccess -ResourceGroupName $snapshotResourceGroupName -SnapshotName $osSnapshotName  -DurationInSecond $sasExpiryDuration -Access Read     
    $progress = Start-AzureStorageBlobCopy -AbsoluteUri $osSAS.AccessSAS -DestContainer $storageContainerName -DestContext $destinationContext -DestBlob $osVHDFileName
   
    while (($progress | Get-AzureStorageBlobCopyState).Status -eq "Pending") {
        Start-Sleep -s 30
        $progress | Get-AzureStorageBlobCopyState
    }

    Write-Host "Copying Data Disk" -ForegroundColor Green

    $dataSAS = Grant-AzureRmSnapshotAccess -ResourceGroupName $snapshotResourceGroupName -SnapshotName $dataSnapshotName  -DurationInSecond $sasExpiryDuration -Access Read 
    $progress = Start-AzureStorageBlobCopy -AbsoluteUri $dataSAS.AccessSAS -DestContainer $storageContainerName -DestContext $destinationContext -DestBlob $dataVHDFileName
    while (($progress | Get-AzureStorageBlobCopyState).Status -eq "Pending") {
        Start-Sleep -s 30
        $progress | Get-AzureStorageBlobCopyState
    }
}




