Param(
    [string] $subscriptionId,
    [ValidateSet('na', 'ga', 'emea', 'ea')]
    [string]$region = 'na',
    [ValidateSet('xp', 'xc')]
    [Parameter(Mandatory = $true)]
    [string]$demoType,
    [Parameter(Mandatory = $true)]
    [string] $version,
    [string] $virtualMachineSize = "Standard_D4s_v3",
    [Parameter(Mandatory = $true)]
    [string] $sourceSnapshotSubscriptionId = "***REMOVED***",    
    [string] $deploymentName = "habitathome",
    [string] $sourceSnapshotPrefix = "habitathome"
)

Import-Module -Name AzureRM -MaximumVersion 6.3.0 -Force

$account = Get-AzureRMContext | Select-Object Account

if ($null -eq $account.Account) {
    Login-AzureRmAccount
}

#Provide the size of the virtual machine
#Get all the vm sizes in a region using below script:
#e.g. Get-AzureRmVMSize -Location eastus 
# available regions are "eastus", "australiaeast", "ukwest" and "eastasia"


#########       SHOULD not need to modify the following     #############

###########     Set up the source
$region = $region.ToLower()
$demoType = $demoType.ToLower()

switch ($region) {
    na {
        $storageAccountId = ("/subscriptions/{0}/resourceGroups/habitathome-demo-snapshot/providers/Microsoft.Storage/storageAccounts/habitathomedemosnapshots" -f $sourceSnapshotSubscriptionId)
        $storageContainerName = "habitathomedemosnapshots"
        $location = "eastus"
        $timeZone = "Eastern Standard Time"
    }
    ga {
        $storageAccountId = ("/subscriptions/{0}/resourceGroups/habitathome-demo-snapshot-ga/providers/Microsoft.Storage/storageAccounts/hhdemosnapshotsga" -f $sourceSnapshotSubscriptionId)
        $storageContainerName = "hhdemosnapshotsga"
        $location = "australiaeast"
        $timeZone = "E. Australia Standard Time"
    }
    emea {
        $storageAccountId = ("/subscriptions/{0}/resourceGroups/habitathome-demo-snapshot-emea/providers/Microsoft.Storage/storageAccounts/hhdemosnapshotsemea" -f $sourceSnapshotSubscriptionId)
        $storageContainerName = "hhdemosnapshotsemea"
        $location = "ukwest"
        $timeZone = "GMT Standard Time"
    }

    ea {
        $storageAccountId = ("/subscriptions/{0}/resourceGroups/habitathome-demo-snapshot-eastasia/providers/Microsoft.Storage/storageAccounts/hhdemosnapshoteastasia" -f $sourceSnapshotSubscriptionId)
        $storageContainerName = "hhdemosnapshoteastasia"
        $location = "eastasia"
        $timeZone = "China Standard Time"

    }
}
$snapshotPrefix = ("{0}{1}" -f $sourceSnapshotPrefix, $demoType)

#Provide the name of the snapshot that will be used to create OS disk
$osVHDUri = ("https://{0}.blob.core.windows.net/snapshots/{1}-{2}-os.vhd" -f $storageContainerName, $snapshotPrefix, $version)

$resourceGroupName = $deploymentName

#Provide the name of the OS and data disks that will be created using the snapshot
$osDiskName = ("{0}_osDisk" -f $deploymentName.Replace("-", "_"))


#Provide the name of an existing virtual network where virtual machine will be created
$virtualNetworkName = ("{0}-vnet" -f $deploymentName)

#Provide the name of the virtual machine
$virtualMachineName = ("{0}-vm" -f $deploymentName)


Function Enable-AzureRMVmAutoShutdown {
    Param 
    (
        [Parameter(Mandatory = $true)] 
        [string] $SubscriptionId,
        [Parameter(Mandatory = $true)] 
        [string] $ResourceGroupName,
        [Parameter(Mandatory = $true)]
        [string] $VirtualMachineName,
        [int] $ShutdownTime = 2200,
        [string] $TimeZone = 'UTC'
    )
    Try {
        $Location = (Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName).Location
        $VMResourceId = (Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VirtualMachineName).Id
        $ScheduledShutdownResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/microsoft.devtestlab/schedules/shutdown-computevm-$VirtualMachineName"

        $Properties = @{}
        $Properties.Add('status', 'Enabled')
        $Properties.Add('taskType', 'ComputeVmShutdownTask')
        $Properties.Add('dailyRecurrence', @{'time' = $ShutdownTime})
        $Properties.Add('timeZoneId', $TimeZone)
        $Properties.Add('notificationSettings', @{status = 'Disabled'; timeInMinutes = 15})
        $Properties.Add('targetResourceId', $VMResourceId)
    
        New-AzureRmResource -Location $Location -ResourceId $ScheduledShutdownResourceId -Properties $Properties -Force
    }
    Catch {Write-Error $_}

}


Write-Host "Selecting Azure Subscription" -ForegroundColor Green
Write-Host ("Creating new deployment '{0}' in '{1}' location" -f $deploymentName, $location) -ForegroundColor Green
#Set the context to the subscription Id where Managed Disks and VM will be created
Select-AzureRmSubscription -SubscriptionId $subscriptionId

Write-Host "Creating ResourceGroup" -ForegroundColor Green
New-AzureRmResourceGroup -Name $resourceGroupName -Location $location


#Create a public IP for the VM
Write-Host "Creating Public IP Address" -ForegroundColor Green
New-AzureRmPublicIpAddress -Name ("{0}_ip" -f $deploymentName) -ResourceGroupName $resourceGroupName -Location $location -AllocationMethod Static
$publicIp = Get-AzureRmPublicIpAddress -Name ("{0}_ip" -f $deploymentName) -ResourceGroupName $resourceGroupName
#Get the virtual network where virtual machine will be hosted
Write-Host "Creating Virtual Network" -ForegroundColor Green
New-AzureRmVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix 10.0.0.0/24
$vnet = Get-AzureRmVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName 
Add-AzureRmVirtualNetworkSubnetConfig -Name sNet -VirtualNetwork $vnet -AddressPrefix 10.0.0.0/24
$vnet | Set-AzureRmVirtualNetwork

Write-Host "Setting up Network Security Rules" -ForegroundColor Green

# set up network security rules and group
$http = New-AzureRmNetworkSecurityRuleConfig  -Name "HTTP" -Description "Allow inbound HTTP" -Protocol Tcp -SourcePortRange * -DestinationPortRange 80 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 101 -Direction Inbound 
$https = New-AzureRmNetworkSecurityRuleConfig -Name "HTTPS" -Description "Allow inbound HTTPS" -Protocol Tcp -SourcePortRange * -DestinationPortRange 443 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 105 -Direction Inbound 
$commerce = New-AzureRmNetworkSecurityRuleConfig -Name "Commerce" -Description "Allow Commerce Ports" -Protocol Tcp -SourcePortRange * -DestinationPortRange 5000-5100 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 110 -Direction Inbound
$idserver = New-AzureRmNetworkSecurityRuleConfig -Name "IdentityServer" -Description "Allow Identity Server Ports" -Protocol Tcp -SourcePortRange * -DestinationPortRange 4200 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 120 -Direction Inbound
$rdp = New-AzureRmNetworkSecurityRuleConfig -Name "rdp" -Description "Allow RDP" -Protocol Tcp -SourcePortRange * -DestinationPortRange 3389 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 1000 -Direction Inbound

$smtpOutbound = New-AzureRmNetworkSecurityRuleConfig -Name "SMTP" -Description "Allow SMTP" -Protocol Tcp -SourcePortRange * -DestinationPortRange 25 -SourceAddressPrefix * -DestinationAddressPrefix * -Access Allow -Priority 1140 -Direction Outbound 

$networkSecurityGroupName = ("{0}-nsg" -f $deploymentName)

if ($demoType -eq "xc") {
    # Only open ports 50xx and 4200 for an XC demo 
    $nsg = New-AzureRmNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName  -Location  $location `
        -SecurityRules $http, $https, $commerce, $idserver, $rdp, $smtpOutbound
}
else {
    $nsg = New-AzureRmNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName  -Location  $location `
        -SecurityRules $http, $https, $rdp, $smtpOutbound
}

$vnet = Get-AzureRmVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName


Write-Host "Creating NIC" -ForegroundColor Green
# Create NIC in the first subnet of the virtual network
$nicName = $deploymentName.Replace("-", "_")
New-AzureRmNetworkInterface -Name ("{0}_nic" -f $nicName)  -ResourceGroupName $resourceGroupName -Location $location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $publicIp.Id -NetworkSecurityGroupId $nsg.Id
$nic = Get-AzureRmNetworkInterface -Name ("{0}_nic" -f $nicName) -ResourceGroupName $resourceGroupName 

Write-Host "Creating OS Disk" -ForegroundColor Green
# OS Disk
New-AzureRmDisk -DiskName $osDiskName -Disk `
(New-AzureRmDiskConfig -AccountType Premium_LRS  `
        -Location $location -CreateOption Import `
        -StorageAccountId $storageAccountId `
        -SourceUri $osVHDUri) `
    -ResourceGroupName $resourceGroupName
$osDisk = Get-AzureRMDisk -DiskName $osDiskName -ResourceGroupName $resourceGroupName

Write-Host "Setting VM Configuration" -ForegroundColor Green
#Initialize virtual machine configuration
$VirtualMachine = New-AzureRmVMConfig -VMName $virtualMachineName -VMSize $virtualMachineSize
$VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -ManagedDiskId $osDisk.Id -CreateOption Attach -Windows
$VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $nic.Id

#Create the virtual machine with Managed Disk
Write-Host "Creating Virtual Machine" -ForegroundColor Green
New-AzureRmVM -VM $VirtualMachine -ResourceGroupName $resourceGroupName -Location $location

Write-Host "Enabling Auto-Shutdown" -ForegroundColor Green
Enable-AzureRMVmAutoShutdown -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -VirtualMachineName $virtualMachineName -TimeZone $timeZone