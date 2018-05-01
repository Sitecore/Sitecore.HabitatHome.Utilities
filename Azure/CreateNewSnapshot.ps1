Param(
    [string] $subscriptionId,
    [string] $sourceResourceGroupNamePrefix = "habitathome",
    [string] $snapshotPrefix = "habitathome",
    [string] $location = "eastus",
    [string] $snapshotDestinationResourceGroup = "habitathome-demo-snapshot",
    [ValidateSet('xp', 'xc')]
    [string]$demoType
)
$account = Get-AzureRMContext | Select-Object Account

if ($account.Account -eq $null) {
    Login-AzureRmAccount
}
$demoType = $demoType.ToLower()
$location = $location.ToLower()
$sourceResourceGroupName = ("{0}{1}master" -f $sourceResourceGroupNamePrefix, $demoType)
$vmName = ("{0}-vm" -f $sourceResourceGroupName)

$osSnapshotName = ("{0}{1}-os-snapshot" -f $snapshotPrefix, $demoType)
$dataSnapshotName = ("{0}{1}-data-snapshot" -f $snapshotPrefix, $demoType)

Select-AzureRmSubscription -SubscriptionId $subscriptionId

$vm = Get-AzureRmVM -ResourceGroupName $sourceResourceGroupName -Name $vmName

$osDiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id
$dataDiskId = $vm.StorageProfile.DataDisks[0].ManagedDisk.Id

$osSnapshotConfig = New-AzureRmSnapshotConfig `
    -SourceUri $osDiskId `
    -Location $location `
    -CreateOption copy

New-AzureRmSnapshot -Snapshot $osSnapshotConfig -SnapshotName $osSnapshotName -ResourceGroupName $snapshotDestinationResourceGroup

$dataSnapshotConfig = New-AzureRmSnapshotConfig `
    -SourceUri $dataDiskId `
    -Location $location `
    -CreateOption copy

New-AzureRmSnapshot -Snapshot $dataSnapshotConfig -SnapshotName $dataSnapshotName -ResourceGroupName $snapshotDestinationResourceGroup