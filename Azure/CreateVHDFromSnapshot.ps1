Param(
    [string] $subscriptionId,
    [string] $deploymentName = "habitathome"
)
$account = Get-AzureRMContext | Select-Object Account

if ($account.Account -eq $null){
    Login-AzureRmAccount
}

$snapshotResourceGroupName = ("{0}-demo-snapshot" -f $deploymentName)

$osSnapshotName = ("{0}-os-snapshot" -f $deploymentName)
$dataSnapshotName= ("{0}-data-snapshot" -f $deploymentName)

$sasExpiryDuration = "3600"

#Provide storage account name where you want to copy the snapshot. 
$storageAccountName = "habitathomedemosnapshots"

#Name of the storage container where the downloaded snapshot will be stored
$storageContainerName = "snapshots"

#Provide the key of the storage account where you want to copy snapshot. 
$storageAccountKey = 'x94hCThqN2kA1dCRknLGRmZ2mMKAGH2r85989gw47N/OKNhj838OU8xM6Gv0QTZjE5TN1Vog8WpLs1hKwNhx+w=='

#Provide the name of the VHD file to which snapshot will be copied.
$osVHDFileName = ("{0}-os.vhd" -f $deploymentName)
$dataVHDFileName=("{0}-data.vhd" -f $deploymentName)

Select-AzureRmSubscription -SubscriptionId $subscriptionId

Write-Host "Generating SAS tokens for snapshot(s)..." -ForegroundColor Green

$osSAS = Grant-AzureRmSnapshotAccess -ResourceGroupName $snapshotResourceGroupName -SnapshotName $osSnapshotName  -DurationInSecond $sasExpiryDuration -Access Read 

$dataSAS = Grant-AzureRmSnapshotAccess -ResourceGroupName $snapshotResourceGroupName -SnapshotName $dataSnapshotName  -DurationInSecond $sasExpiryDuration -Access Read 

#Create the context for the storage account which will be used to copy snapshot to the storage account 
$destinationContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

Write-Host "Copying VHDs - this will take a while... " -ForegroundColor Green
Write-Host "Copying OS Disk" -ForegroundColor Green

$progress = Start-AzureStorageBlobCopy -AbsoluteUri $osSAS.AccessSAS -DestContainer $storageContainerName -DestContext $destinationContext -DestBlob $osVHDFileName
$progress | Get-AzureStorageBlobCopyState -WaitForComplete

Write-Host "Copying Data Disk" -ForegroundColor Green

$progress = Start-AzureStorageBlobCopy -AbsoluteUri $dataSAS.AccessSAS -DestContainer $storageContainerName -DestContext $destinationContext -DestBlob $dataVHDFileName
$progress | Get-AzureStorageBlobCopyState -WaitForComplete