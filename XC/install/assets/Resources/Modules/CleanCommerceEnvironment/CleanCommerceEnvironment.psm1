
Function Invoke-CleanCommerceEnvironmentTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UrlCommerceShopsServicesCleanEnvironment,
        [string[]]$Environments
    )
    Write-Host "Cleaning Commerce Services: $($UrlCommerceShopsServicesCleanEnvironment)" -ForegroundColor Yellow    
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", $global:sitecoreIdToken)

    foreach ($env in $Environments) {
        $params = @{"environment"="$env"} | ConvertTo-Json
    
        Invoke-RestMethod $UrlCommerceShopsServicesCleanEnvironment -TimeoutSec 1200 -Method POST -Headers $headers -Body $params -ContentType "application/json"
    }

    Write-Host "Clean Commerce Services Environment completed" -ForegroundColor Green
}


Register-SitecoreInstallExtension -Command Invoke-CleanCommerceEnvironmentTask -As CleanCommerceEnvironment -Type Task -Force
