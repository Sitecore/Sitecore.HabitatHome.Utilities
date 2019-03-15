Param(
    [string] $ProgressPreference
)
Write-Verbose ("Setting Progress Preference to {0}" -f $ProgressPreference)
$Global:ProgressPreference = $ProgressPreference