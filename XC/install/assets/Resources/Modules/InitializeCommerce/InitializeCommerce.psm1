
Function Invoke-UpdateShopsPortTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EngineConnectIncludeDir,
        [Parameter(Mandatory = $true)]
        [string]$CommerceAuthoringServicesPort                  
    )      

    $pathToConfig = $(Join-Path -Path $EngineConnectIncludeDir -ChildPath "\Sitecore.Commerce.Engine.Connect.config") 
    $xml = [xml](Get-Content $pathToConfig)

    $node = $xml.configuration.sitecore.commerceEngineConfiguration
    $node.shopsServiceUrl = $node.shopsServiceUrl.replace("5000", $CommerceAuthoringServicesPort)
    $node.commerceOpsServiceUrl = $node.commerceOpsServiceUrl.replace("5000", $CommerceAuthoringServicesPort)
    $xml.Save($pathToConfig)      
}

Function Invoke-ApplyCertificateTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EngineConnectIncludeDir,
        [Parameter(Mandatory = $true)]
        [string]$CertificatePath,
        [Parameter(Mandatory = $true)]
        [string[]]$CommerceServicesPathCollection
    )      

    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
    $cert.Import($CertificatePath)

    Write-Host "Applying certificate: $($cert.Thumbprint)" -ForegroundColor Green

    $pathToConfig = $(Join-Path -Path $EngineConnectIncludeDir -ChildPath "\Sitecore.Commerce.Engine.Connect.config") 
    $xml = [xml](Get-Content $pathToConfig)
    $node = $xml.configuration.sitecore.commerceEngineConfiguration
    $node.certificateThumbprint = $cert.Thumbprint
    $xml.Save($pathToConfig)  
    foreach ($path in $CommerceServicesPathCollection) {
        $pathToJson = $(Join-Path -Path $path -ChildPath "wwwroot\config.json") 
        $originalJson = Get-Content $pathToJson -Raw | ConvertFrom-Json
        $certificateNode = $originalJson.Certificates.Certificates[0]
        $certificateNode.Thumbprint = $cert.Thumbprint       
        $originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $pathToJson
    } 
}

Function Invoke-GetIdServerTokenTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject[]]$SitecoreAdminAccount,
        [Parameter(Mandatory = $true)]
        [string]$UrlIdentityServerGetToken        
    )

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Content-Type", 'application/x-www-form-urlencoded')
    $headers.Add("Accept", 'application/json')

    $body = @{
        password   = $SitecoreAdminAccount.password
        grant_type = 'password'
        username   = $SitecoreAdminAccount.userName
        client_id  = 'postman-api'
        scope      = 'openid EngineAPI postman_api'
    }

    Write-Host "Get Token From Sitecore.IdentityServer" -ForegroundColor Green
    $response = Invoke-RestMethod $UrlIdentityServerGetToken -Method Post -Body $body -Headers $headers

    $global:sitecoreIdToken = "Bearer {0}" -f $response.access_token
}

Function Invoke-BootStrapCommerceServicesTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UrlCommerceShopsServicesBootstrap        
    )
	
    Write-Host "BootStrapping Commerce Services: $($urlCommerceShopsServicesBootstrap)" -ForegroundColor Yellow
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", $global:sitecoreIdToken)
    Invoke-RestMethod $UrlCommerceShopsServicesBootstrap -TimeoutSec 1200 -Method PUT -Headers $headers
    Write-Host "Commerce Services BootStrapping completed" -ForegroundColor Green
}

Function Invoke-InitializeCommerceServicesTask {
    [CmdletBinding()]
    param(        
        [Parameter(Mandatory = $true)]
        [string]$UrlInitializeEnvironment,
        [Parameter(Mandatory = $true)]
        [string]$UrlCheckCommandStatus,
        [Parameter(Mandatory = $true)]
        [string[]]$Environments)

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", $global:sitecoreIdToken);

    foreach ($env in $Environments) {
        Write-Host "Initializing $($env) ..." -ForegroundColor Yellow

        $initializeUrl = $UrlInitializeEnvironment -replace "envNameValue", $env
        $result = Invoke-RestMethod $initializeUrl -TimeoutSec 1200 -Method Get -Headers $headers -ContentType "application/json"
        $checkUrl = $UrlCheckCommandStatus -replace "taskIdValue", $result.TaskId

        $sw = [system.diagnostics.stopwatch]::StartNew()
        $tp = New-TimeSpan -Minute 10
        do {
            Start-Sleep -s 30
            Write-Host "Checking if $($checkUrl) has completed ..." -ForegroundColor White
            $result = Invoke-RestMethod $checkUrl -TimeoutSec 1200 -Method Get -Headers $headers -ContentType "application/json"

            if ($result.ResponseCode -ne "Ok") {
                $(throw Write-Host "Initialize environment $($env) failed, please check Engine service logs for more info." -Foregroundcolor Red)
            }
        } while ($result.Status -ne "RanToCompletion" -and $sw.Elapsed -le $tp)

        Write-Host "Initialization for $($env) completed ..." -ForegroundColor Green
    }

    Write-Host "Initialization completed ..." -ForegroundColor Green 
}

Function Invoke-EnableCsrfValidationTask {
    [CmdletBinding()]
    param(        
        [Parameter(Mandatory = $true)]
        [string[]]$CommerceServicesPathCollection
    )
    foreach ($path in $CommerceServicesPathCollection) {
        $pathToJson = $(Join-Path -Path $path -ChildPath "wwwroot\config.json")
        $originalJson = Get-Content $pathToJson -Raw  | ConvertFrom-Json
        $originalJson.AppSettings.AntiForgeryEnabled = $true
        $originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $pathToJson
    }
}

Function Invoke-DisableCsrfValidationTask {
    [CmdletBinding()]
    param(        
        [Parameter(Mandatory = $true)]
        [string[]]$CommerceServicesPathCollection
    )
    foreach ($path in $CommerceServicesPathCollection) {
        $pathToJson = $(Join-Path -Path $path -ChildPath "wwwroot\config.json")
        $originalJson = Get-Content $pathToJson -Raw  | ConvertFrom-Json
        $originalJson.AppSettings.AntiForgeryEnabled = $false
        $originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $pathToJson
    }
}

Function Invoke-EnsureSyncDefaultContentPathsTask {
    [CmdletBinding()]
    param(        
        [Parameter(Mandatory = $true)]
        [string]$UrlEnsureSyncDefaultContentPaths,
        [Parameter(Mandatory = $true)]
        [string]$UrlCheckCommandStatus,
        [Parameter(Mandatory = $true)]
        [string[]]$Environments)

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", $global:sitecoreIdToken);
   
    foreach ($env in $Environments) {
        Write-Host "Ensure/Sync default content paths for: $($env)" -ForegroundColor Yellow 

        $ensureUrl = $UrlEnsureSyncDefaultContentPaths -replace "envNameValue", $env
        $result = Invoke-RestMethod $ensureUrl -TimeoutSec 1200 -Method PUT -Headers $headers  -ContentType "application/json" 
        $checkUrl = $UrlCheckCommandStatus -replace "taskIdValue", $result.TaskId

        $sw = [system.diagnostics.stopwatch]::StartNew()
        $tp = New-TimeSpan -Minute 10
        do {
            Start-Sleep -s 30
            Write-Host "Checking if $($checkUrl) has completed ..." -ForegroundColor White
            $result = Invoke-RestMethod $checkUrl -TimeoutSec 1200 -Method Get -Headers $headers -ContentType "application/json"

            if ($result.ResponseCode -ne "Ok") {
                $(throw Write-Host "Ensure/Sync default content paths for environment $($env) failed, please check Engine service logs for more info." -Foregroundcolor Red)
            }
            
        } while ($result.Status -ne "RanToCompletion" -and $sw.Elapsed -le $tp)

        Write-Host "Ensure/Sync default content paths for $($env) completed ..." -ForegroundColor Green
    }

    Write-Host "Ensure/Sync default content paths completed ..." -ForegroundColor Green
}

Register-SitecoreInstallExtension -Command Invoke-UpdateShopsPortTask -As UpdateShopsPort -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-ApplyCertificateTask -As ApplyCertificate -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-GetIdServerTokenTask -As GetIdServerToken -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-BootStrapCommerceServicesTask -As BootStrapCommerceServices -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-InitializeCommerceServicesTask -As InitializeCommerceServices -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-EnableCsrfValidationTask -As EnableCsrfValidation -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-DisableCsrfValidationTask -As DisableCsrfValidation -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-EnsureSyncDefaultContentPathsTask -As EnsureSyncDefaultContentPaths -Type Task -Force