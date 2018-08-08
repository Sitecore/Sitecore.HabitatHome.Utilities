Param(
    [string] $subscriptionId,
    [string] $sourceResourceGroupNamePrefix = "habitathome",
    [string] $snapshotPrefix = "habitathome",
    [string] $location = "eastus",
    [string] $snapshotDestinationResourceGroup = "habitathome-demo-snapshot",
    [ValidateSet('xp', 'xc')]
    [string] $demoType,
    [string] $suffix = "master",
	[Parameter(Mandatory = $true)]
    [string] $version
)
$account = Get-AzureRMContext | Select-Object Account

if ($null -eq $account.Account) {
    Login-AzureRmAccount
}
$demoType = $demoType.ToLower()
$location = $location.ToLower()
$sourceResourceGroupName = ("{0}{1}{2}" -f $sourceResourceGroupNamePrefix, $demoType, $suffix)
$vmName = ("{0}-vm" -f $sourceResourceGroupName)

$osSnapshotName = ("{0}{1}-{2}-os-snapshot" -f $snapshotPrefix, $demoType, $version)

Select-AzureRmSubscription -SubscriptionId $subscriptionId

$vm = Get-AzureRmVM -ResourceGroupName $sourceResourceGroupName -Name $vmName

$osDiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id

$osSnapshotConfig = New-AzureRmSnapshotConfig `
    -SourceUri $osDiskId `
    -Location $location `
    -CreateOption copy

New-AzureRmSnapshot -Snapshot $osSnapshotConfig -SnapshotName $osSnapshotName -ResourceGroupName $snapshotDestinationResourceGroup