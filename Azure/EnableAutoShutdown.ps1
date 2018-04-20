
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
