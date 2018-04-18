Param(
    [string] $subscriptionId,
    [string] $sourceResourceGroupName = "habitathome"
)
$account = Get-AzureRMContext | Select-Object Account

if ($account.Account -eq $null){
    Login-AzureRmAccount
}

$location = "eastus"

$vmName =  ("{0}-vm" -f $sourceResourceGroupName)

$osSnapshotName = "habitathome-os-snapshot"
$dataSnapshotName= "habitathome-data-snapshot"

#Provide storage account name where you want to copy the snapshot. 
$snapshotResourceGroupName = "habitathome-demo-snapshot"

Select-AzureRmSubscription -SubscriptionId $subscriptionId

$vm = Get-AzureRmVM -ResourceGroupName $sourceResourceGroupName -Name $vmName

$osDiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id
$dataDiskId = $vm.StorageProfile.DataDisks[0].ManagedDisk.Id

$osSnapshotConfig =  New-AzureRmSnapshotConfig `
-SourceUri $osDiskId `
-Location $location `
-CreateOption copy

New-AzureRmSnapshot -Snapshot $osSnapshotConfig -SnapshotName $osSnapshotName -ResourceGroupName $snapshotResourceGroupName

$dataSnapshotConfig =  New-AzureRmSnapshotConfig `
-SourceUri $dataDiskId `
-Location $location `
-CreateOption copy

New-AzureRmSnapshot -Snapshot $dataSnapshotConfig -SnapshotName $dataSnapshotName -ResourceGroupName $snapshotResourceGroupName