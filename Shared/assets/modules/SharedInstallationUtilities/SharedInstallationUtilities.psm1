
Function Invoke-StringReplaceConfigFunction {
    param(
        [Parameter(Mandatory = $true)]
        [string]$source,
        [Parameter(Mandatory = $true)]
        [string]$search,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$replace

    )

    Write-Verbose -Message $PSCmdlet.MyInvocation.MyCommand
    
    Write-Verbose "Searching for: $search in string: $source to replace with $replace"

    $result = $null
    $result = $source -replace $search, $replace
    

    Write-Verbose "Result: $result"
    return $result
}

Function Invoke-GetSitecoreModuleDetailsConfigFunction {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$assets,
        [Parameter(Mandatory = $true)]
        [string]$moduleId
    )
    Write-Verbose -Message $PSCmdlet.MyInvocation.MyCommand
    Write-Verbose "Getting module: $moduleId"
    
    $assets = ConvertTo-Json -InputObject $assets | ConvertFrom-Json

    $result = $null
    $result = $assets.modules | Where-Object { $_.id -eq $moduleId}

    Write-Verbose "Result: $($result.Name)"
    return $result
}

Function Invoke-GetObjectPropertyConfigFunction {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$module,
        [Parameter(Mandatory = $true)]
        [string]$field
    )
    Write-Verbose -Message $PSCmdlet.MyInvocation.MyCommand
    
    Write-Verbose "Getting property $field in  module"

    $result = $null
    $result = $module.$field

    Write-Verbose "Result: $result"
    return $result
}


Register-SitecoreInstallExtension -Command Invoke-GetFilePathConfigFunction -As GetFilePath -Type ConfigFunction -Force
Register-SitecoreInstallExtension -Command Invoke-GetSitecoreModuleDetailsConfigFunction -As GetSitecoreModuleDetails -Type ConfigFunction -Force
Register-SitecoreInstallExtension -Command Invoke-GetObjectPropertyConfigFunction -As GetObjectProperty -Type ConfigFunction -Force
Register-SitecoreInstallExtension -Command Invoke-StringReplaceConfigFunction -As ReplaceString -Type ConfigFunction -Force

