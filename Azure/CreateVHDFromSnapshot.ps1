Param(
    [string] $subscriptionId,
    [string] $snapshotPrefix = "habitathome",
    [ValidateSet('xp', 'xc')]
    [string]$demoType,
    [string[]] $regions = @("na", "emea", "ga", "ne")
    
    
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



if (Test-Path (Join-Path $PWD "vhdcreation.log") -PathType Leaf) {
    Remove-Item (Join-Path $PWD "vhdcreation.log") -Force
}
foreach ($region in $regions) {
    $region = $region.ToLower()
    $configRegion = ($config.regions | Where-Object {$_.name -eq $region})
    Write-Host ("Creating VHDs in {0}" -f $configRegion.location) -ForegroundColor Green
    $storageAccountName = $configRegion.StorageAccountName
    $keys = Get-AzureRmStorageAccountKey -ResourceGroupName $configRegion.resourceGroupName -Name $configRegion.StorageAccountName
    $storageAccountKey = $keys[0].Value
    $storageContainerName = $configRegion.StorageContainerName

    #Create the context for the storage account which will be used to copy snapshot to the storage account 
    $destinationContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey

    Write-Host "Copying VHDs - this will take a while... " -ForegroundColor Green
    Write-Host "Copying OS Disk" -ForegroundColor Green
    Write-Host "Generating SAS tokens for snapshot(s)..." -ForegroundColor Green
  
    $DebugPreference = 'Continue'
  
    $result = Grant-AzureRmSnapshotAccess -ResourceGroupName $snapshotResourceGroupName -SnapshotName $osSnapshotName -Access 'Read' -DurationInSecond $sasExpiryDuration 5>&1
  
    $DebugPreference = 'SilentlyContinue'
  
    $sasUri = ((($result | where {$_ -match "accessSAS"})[-1].ToString().Split("`n") | where {$_ -match "accessSAS"}).Split(' ') | where {$_ -match "https"}).Replace('"','')
  
    #$osSAS = Grant-AzureRmSnapshotAccess -ResourceGroupName $snapshotResourceGroupName -SnapshotName $osSnapshotName -DurationInSecond $sasExpiryDuration -Access Read
   # $osSAS=$(az snapshot grant-access -g $snapshotResourceGroupName -n $osSnapshotName --duration-in-seconds $sasExpiryDuration -o tsv)

    #$osSAS = Grant-AzureRmSnapshotAccess -ResourceGroupName $snapshotResourceGroupName -SnapshotName $osSnapshotName  -DurationInSecond $sasExpiryDuration -Access Read -Verbose
#    Write-Host ("SAS Token: {0}" -f $osSAS.AccessSAS)    
 #   Write-Host ("SAS Token: {0}" -f $osSAS)    
    $progress = Start-AzureStorageBlobCopy -AbsoluteUri $sasUri -DestContainer $storageContainerName -DestContext $destinationContext -DestBlob $osVHDFileName -Force
   
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
    
    $result = ($progress | Get-AzureStorageBlobCopyState)
    
    if ($result.Status -eq "Success") {
        Write-Host ("Successful copy of Data Disk to {0}" -f $configRegion.location) -ForegroundColor Green
    }
    else {
        $message = ("Error copying data disk to region {0}" -f $configRegion.location)
        Write-Host $message -ForegroundColor Red
        Add-Content -Path (Join-Path $PWD "vhdcreation.log") -Value $message -Force
    }
}