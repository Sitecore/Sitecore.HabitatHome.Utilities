
Function Invoke-UpdateShopsHostnameTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EngineConnectIncludeDir,
        [Parameter(Mandatory = $true)]
        [string]$CommerceServicesHostPostfix                   
    )      

    $pathToConfig = $(Join-Path -Path $EngineConnectIncludeDir -ChildPath "\Sitecore.Commerce.Engine.Connect.config") 
    $xml = [xml](Get-Content $pathToConfig)

    $node = $xml.configuration.sitecore.commerceEngineConfiguration
    $node.shopsServiceUrl = $node.shopsServiceUrl -replace "localhost:5000", "commerceauthoring.$CommerceServicesHostPostfix"
    $node.commerceOpsServiceUrl = $node.commerceOpsServiceUrl -replace "localhost:5000", "commerceauthoring.$CommerceServicesHostPostfix"
    $xml.Save($pathToConfig)      
}

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
    $node.shopsServiceUrl = $node.shopsServiceUrl -replace "5000", $CommerceAuthoringServicesPort
    $node.commerceOpsServiceUrl = $node.commerceOpsServiceUrl -replace "5000", $CommerceAuthoringServicesPort
    $xml.Save($pathToConfig)      
}

Function Invoke-ApplyCertificateTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$EngineConnectIncludeDir,
        [Parameter(Mandatory = $true)]
        [string]$CertificateThumbprint,
        [Parameter(Mandatory = $true)]
        [string[]]$CommerceServicesPathCollection
    )      

    Write-Host "Applying certificate: $($CertificateThumbprint)" -ForegroundColor Green

    $pathToConfig = $(Join-Path -Path $EngineConnectIncludeDir -ChildPath "\Sitecore.Commerce.Engine.Connect.config") 
    $xml = [xml](Get-Content $pathToConfig)
    $node = $xml.configuration.sitecore.commerceEngineConfiguration
    $node.certificateThumbprint = $CertificateThumbprint
    $xml.Save($pathToConfig)  

    foreach ($path in $CommerceServicesPathCollection) {
        $pathToJson = $(Join-Path -Path $path -ChildPath "wwwroot\config.json") 
        $originalJson = Get-Content $pathToJson -Raw | ConvertFrom-Json
        $certificateNode = $originalJson.Certificates.Certificates[0]
        $certificateNode.Thumbprint = $CertificateThumbprint      
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
    Write-Host "Bearer {0} "$response.access_token -ForegroundColor Green

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

        $initializeUrl = $UrlInitializeEnvironment

        $payload = @{
            "environment"=$env;
        }

        $result = Invoke-RestMethod $initializeUrl -TimeoutSec 1200 -Method POST -Body ($payload|ConvertTo-Json) -Headers $headers -ContentType "application/json"
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

Function Invoke-IndexCatalogItemsTask {
    [CmdletBinding()]
    param(        
        [Parameter(Mandatory = $true)]
        [string]$UrlRunMinion,
        [Parameter(Mandatory = $true)]
        [string[]]$MinionEnvironments)

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", $global:sitecoreIdToken);

    foreach ($env in $MinionEnvironments) {
        Write-Host "Indexing $($env) ..." -ForegroundColor Yellow

        $payload = @{            
            'minionFullName'='Sitecore.Commerce.Plugin.Search.FullIndexMinion, Sitecore.Commerce.Plugin.Search';
            'environmentName'=$env;
            'policies'=@(@{
                '$type'='Sitecore.Commerce.Core.RunMinionPolicy, Sitecore.Commerce.Core';
                'WithListToWatch'='CatalogItems';
            })
        }

        $result = Invoke-RestMethod $UrlRunMinion -TimeoutSec 1200 -Method POST -Body ($payload|ConvertTo-Json) -Headers $headers -ContentType "application/json"

        Write-Host "Indexing for $($env) completed ..." -ForegroundColor Green
    }

    Write-Host "Indexing completed ..." -ForegroundColor Green 
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

Register-SitecoreInstallExtension -Command Invoke-UpdateShopsHostnameTask -As UpdateShopsHostname -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-UpdateShopsPortTask -As UpdateShopsPort -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-ApplyCertificateTask -As ApplyCertificate -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-GetIdServerTokenTask -As GetIdServerToken -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-BootStrapCommerceServicesTask -As BootStrapCommerceServices -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-InitializeCommerceServicesTask -As InitializeCommerceServices -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-IndexCatalogItemsTask -As IndexCatalogItems -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-EnableCsrfValidationTask -As EnableCsrfValidation -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-DisableCsrfValidationTask -As DisableCsrfValidation -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-EnsureSyncDefaultContentPathsTask -As EnsureSyncDefaultContentPaths -Type Task -Force
# SIG # Begin signature block
# MIIXwQYJKoZIhvcNAQcCoIIXsjCCF64CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUR2wiDjPq+6XOZOBiqCYVHZok
# OWSgghL8MIID7jCCA1egAwIBAgIQfpPr+3zGTlnqS5p31Ab8OzANBgkqhkiG9w0B
# AQUFADCBizELMAkGA1UEBhMCWkExFTATBgNVBAgTDFdlc3Rlcm4gQ2FwZTEUMBIG
# A1UEBxMLRHVyYmFudmlsbGUxDzANBgNVBAoTBlRoYXd0ZTEdMBsGA1UECxMUVGhh
# d3RlIENlcnRpZmljYXRpb24xHzAdBgNVBAMTFlRoYXd0ZSBUaW1lc3RhbXBpbmcg
# Q0EwHhcNMTIxMjIxMDAwMDAwWhcNMjAxMjMwMjM1OTU5WjBeMQswCQYDVQQGEwJV
# UzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFu
# dGVjIFRpbWUgU3RhbXBpbmcgU2VydmljZXMgQ0EgLSBHMjCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBALGss0lUS5ccEgrYJXmRIlcqb9y4JsRDc2vCvy5Q
# WvsUwnaOQwElQ7Sh4kX06Ld7w3TMIte0lAAC903tv7S3RCRrzV9FO9FEzkMScxeC
# i2m0K8uZHqxyGyZNcR+xMd37UWECU6aq9UksBXhFpS+JzueZ5/6M4lc/PcaS3Er4
# ezPkeQr78HWIQZz/xQNRmarXbJ+TaYdlKYOFwmAUxMjJOxTawIHwHw103pIiq8r3
# +3R8J+b3Sht/p8OeLa6K6qbmqicWfWH3mHERvOJQoUvlXfrlDqcsn6plINPYlujI
# fKVOSET/GeJEB5IL12iEgF1qeGRFzWBGflTBE3zFefHJwXECAwEAAaOB+jCB9zAd
# BgNVHQ4EFgQUX5r1blzMzHSa1N197z/b7EyALt0wMgYIKwYBBQUHAQEEJjAkMCIG
# CCsGAQUFBzABhhZodHRwOi8vb2NzcC50aGF3dGUuY29tMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwPwYDVR0fBDgwNjA0oDKgMIYuaHR0cDovL2NybC50aGF3dGUuY29tL1Ro
# YXd0ZVRpbWVzdGFtcGluZ0NBLmNybDATBgNVHSUEDDAKBggrBgEFBQcDCDAOBgNV
# HQ8BAf8EBAMCAQYwKAYDVR0RBCEwH6QdMBsxGTAXBgNVBAMTEFRpbWVTdGFtcC0y
# MDQ4LTEwDQYJKoZIhvcNAQEFBQADgYEAAwmbj3nvf1kwqu9otfrjCR27T4IGXTdf
# plKfFo3qHJIJRG71betYfDDo+WmNI3MLEm9Hqa45EfgqsZuwGsOO61mWAK3ODE2y
# 0DGmCFwqevzieh1XTKhlGOl5QGIllm7HxzdqgyEIjkHq3dlXPx13SYcqFgZepjhq
# IhKjURmDfrYwggSjMIIDi6ADAgECAhAOz/Q4yP6/NW4E2GqYGxpQMA0GCSqGSIb3
# DQEBBQUAMF4xCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3Jh
# dGlvbjEwMC4GA1UEAxMnU3ltYW50ZWMgVGltZSBTdGFtcGluZyBTZXJ2aWNlcyBD
# QSAtIEcyMB4XDTEyMTAxODAwMDAwMFoXDTIwMTIyOTIzNTk1OVowYjELMAkGA1UE
# BhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMTQwMgYDVQQDEytT
# eW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIFNpZ25lciAtIEc0MIIBIjAN
# BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAomMLOUS4uyOnREm7Dv+h8GEKU5Ow
# mNutLA9KxW7/hjxTVQ8VzgQ/K/2plpbZvmF5C1vJTIZ25eBDSyKV7sIrQ8Gf2Gi0
# jkBP7oU4uRHFI/JkWPAVMm9OV6GuiKQC1yoezUvh3WPVF4kyW7BemVqonShQDhfu
# ltthO0VRHc8SVguSR/yrrvZmPUescHLnkudfzRC5xINklBm9JYDh6NIipdC6Anqh
# d5NbZcPuF3S8QYYq3AhMjJKMkS2ed0QfaNaodHfbDlsyi1aLM73ZY8hJnTrFxeoz
# C9Lxoxv0i77Zs1eLO94Ep3oisiSuLsdwxb5OgyYI+wu9qU+ZCOEQKHKqzQIDAQAB
# o4IBVzCCAVMwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAO
# BgNVHQ8BAf8EBAMCB4AwcwYIKwYBBQUHAQEEZzBlMCoGCCsGAQUFBzABhh5odHRw
# Oi8vdHMtb2NzcC53cy5zeW1hbnRlYy5jb20wNwYIKwYBBQUHMAKGK2h0dHA6Ly90
# cy1haWEud3Muc3ltYW50ZWMuY29tL3Rzcy1jYS1nMi5jZXIwPAYDVR0fBDUwMzAx
# oC+gLYYraHR0cDovL3RzLWNybC53cy5zeW1hbnRlYy5jb20vdHNzLWNhLWcyLmNy
# bDAoBgNVHREEITAfpB0wGzEZMBcGA1UEAxMQVGltZVN0YW1wLTIwNDgtMjAdBgNV
# HQ4EFgQURsZpow5KFB7VTNpSYxc/Xja8DeYwHwYDVR0jBBgwFoAUX5r1blzMzHSa
# 1N197z/b7EyALt0wDQYJKoZIhvcNAQEFBQADggEBAHg7tJEqAEzwj2IwN3ijhCcH
# bxiy3iXcoNSUA6qGTiWfmkADHN3O43nLIWgG2rYytG2/9CwmYzPkSWRtDebDZw73
# BaQ1bHyJFsbpst+y6d0gxnEPzZV03LZc3r03H0N45ni1zSgEIKOq8UvEiCmRDoDR
# EfzdXHZuT14ORUZBbg2w6jiasTraCXEQ/Bx5tIB7rGn0/Zy2DBYr8X9bCT2bW+IW
# yhOBbQAuOA2oKY8s4bL0WqkBrxWcLC9JG9siu8P+eJRRw4axgohd8D20UaF5Mysu
# e7ncIAkTcetqGVvP6KUwVyyJST+5z3/Jvz4iaGNTmr1pdKzFHTx/kuDDvBzYBHUw
# ggUrMIIEE6ADAgECAhAHplztCw0v0TJNgwJhke9VMA0GCSqGSIb3DQEBCwUAMHIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJ
# RCBDb2RlIFNpZ25pbmcgQ0EwHhcNMTcwODIzMDAwMDAwWhcNMjAwOTMwMTIwMDAw
# WjBoMQswCQYDVQQGEwJVUzELMAkGA1UECBMCY2ExEjAQBgNVBAcTCVNhdXNhbGl0
# bzEbMBkGA1UEChMSU2l0ZWNvcmUgVVNBLCBJbmMuMRswGQYDVQQDExJTaXRlY29y
# ZSBVU0EsIEluYy4wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC7PZ/g
# huhrQ/p/0Cg7BRrYjw7ZMx8HNBamEm0El+sedPWYeAAFrjDSpECxYjvK8/NOS9dk
# tC35XL2TREMOJk746mZqia+g+NQDPEaDjNPG/iT0gWsOeCa9dUcIUtnBQ0hBKsuR
# bau3n7w1uIgr3zf29vc9NhCoz1m2uBNIuLBlkKguXwgPt4rzj66+18JV3xyLQJoS
# 3ZAA8k6FnZltNB+4HB0LKpPmF8PmAm5fhwGz6JFTKe+HCBRtuwOEERSd1EN7TGKi
# xczSX8FJMz84dcOfALxjTj6RUF5TNSQLD2pACgYWl8MM0lEtD/1eif7TKMHqaA+s
# m/yJrlKEtOr836BvAgMBAAGjggHFMIIBwTAfBgNVHSMEGDAWgBRaxLl7Kgqjpepx
# A8Bg+S32ZXUOWDAdBgNVHQ4EFgQULh60SWOBOnU9TSFq0c2sWmMdu7EwDgYDVR0P
# AQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGA1UdHwRwMG4wNaAzoDGG
# L2h0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtY3MtZzEuY3Js
# MDWgM6Axhi9odHRwOi8vY3JsNC5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVkLWNz
# LWcxLmNybDBMBgNVHSAERTBDMDcGCWCGSAGG/WwDATAqMCgGCCsGAQUFBwIBFhxo
# dHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAgGBmeBDAEEATCBhAYIKwYBBQUH
# AQEEeDB2MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wTgYI
# KwYBBQUHMAKGQmh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFNI
# QTJBc3N1cmVkSURDb2RlU2lnbmluZ0NBLmNydDAMBgNVHRMBAf8EAjAAMA0GCSqG
# SIb3DQEBCwUAA4IBAQBozpJhBdsaz19E9faa/wtrnssUreKxZVkYQ+NViWeyImc5
# qEZcDPy3Qgf731kVPnYuwi5S0U+qyg5p1CNn/WsvnJsdw8aO0lseadu8PECuHj1Z
# 5w4mi5rGNq+QVYSBB2vBh5Ps5rXuifBFF8YnUyBc2KuWBOCq6MTRN1H2sU5LtOUc
# Qkacv8hyom8DHERbd3mIBkV8fmtAmvwFYOCsXdBHOSwQUvfs53GySrnIYiWT0y56
# mVYPwDj7h/PdWO5hIuZm6n5ohInLig1weiVDJ254r+2pfyyRT+02JVVxyHFMCLwC
# ASs4vgbiZzMDltmoTDHz9gULxu/CfBGM0waMDu3cMIIFMDCCBBigAwIBAgIQBAkY
# G1/Vu2Z1U0O1b5VQCDANBgkqhkiG9w0BAQsFADBlMQswCQYDVQQGEwJVUzEVMBMG
# A1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQw
# IgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMTMxMDIyMTIw
# MDAwWhcNMjgxMDIyMTIwMDAwWjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhE
# aWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMIIBIjANBgkq
# hkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA+NOzHH8OEa9ndwfTCzFJGc/Q+0WZsTrb
# RPV/5aid2zLXcep2nQUut4/6kkPApfmJ1DcZ17aq8JyGpdglrA55KDp+6dFn08b7
# KSfH03sjlOSRI5aQd4L5oYQjZhJUM1B0sSgmuyRpwsJS8hRniolF1C2ho+mILCCV
# rhxKhwjfDPXiTWAYvqrEsq5wMWYzcT6scKKrzn/pfMuSoeU7MRzP6vIK5Fe7SrXp
# dOYr/mzLfnQ5Ng2Q7+S1TqSp6moKq4TzrGdOtcT3jNEgJSPrCGQ+UpbB8g8S9MWO
# D8Gi6CxR93O8vYWxYoNzQYIH5DiLanMg0A9kczyen6Yzqf0Z3yWT0QIDAQABo4IB
# zTCCAckwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0l
# BAwwCgYIKwYBBQUHAwMweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRw
# Oi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwgYEGA1Ud
# HwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFz
# c3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNv
# bS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwTwYDVR0gBEgwRjA4BgpghkgB
# hv1sAAIEMCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9D
# UFMwCgYIYIZIAYb9bAMwHQYDVR0OBBYEFFrEuXsqCqOl6nEDwGD5LfZldQ5YMB8G
# A1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMA0GCSqGSIb3DQEBCwUAA4IB
# AQA+7A1aJLPzItEVyCx8JSl2qB1dHC06GsTvMGHXfgtg/cM9D8Svi/3vKt8gVTew
# 4fbRknUPUbRupY5a4l4kgU4QpO4/cY5jDhNLrddfRHnzNhQGivecRk5c/5CxGwcO
# kRX7uq+1UcKNJK4kxscnKqEpKBo6cSgCPC6Ro8AlEeKcFEehemhor5unXCBc2XGx
# DI+7qPjFEmifz0DLQESlE/DmZAwlCEIysjaKJAL+L3J+HNdJRZboWR3p+nRka7Lr
# ZkPas7CM1ekN3fYBIM6ZMWM9CBoYs4GbT8aTEAb8B4H6i9r5gkn3Ym6hU/oSlBiF
# LpKR6mhsRDKyZqHnGKSaZFHvMYIELzCCBCsCAQEwgYYwcjELMAkGA1UEBhMCVVMx
# FTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNv
# bTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUgU2lnbmlu
# ZyBDQQIQB6Zc7QsNL9EyTYMCYZHvVTAJBgUrDgMCGgUAoHAwEAYKKwYBBAGCNwIB
# DDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFPaX3QIlBaKo6iAl8iMoF5gs
# dCxjMA0GCSqGSIb3DQEBAQUABIIBACf+nfSB9h/kUNYLzXXIYGcGLUeXF8ACoouE
# 3uFac5/tO1Lr/w5nl/tmUHhWLBqtn7SdQXCFDBtCrsm5RByoRIo3gP60LSDOMcR9
# u1NZvfzHg5CXBTgXUdh00Y0sx2M/fEd/ypEDEDAhA2wSLE1dHOqa0IeUv967lYJg
# AuAZvevnoA60YDRkiUPR1nFfhJ62Kj2+PdBtpDMP7QZ7751Bij4wGbfpGVDysU0M
# QTzeOOAlCAsKLgtw74f2lw3Kyc8xjnfS8MlhUmh8hRKELGRENnX4iifzCpab0GxQ
# 49MH2nDfLn0R8Nk/4wY8cNFu5/Q+05OSG4qS1u02dvAiA2xCbmKhggILMIICBwYJ
# KoZIhvcNAQkGMYIB+DCCAfQCAQEwcjBeMQswCQYDVQQGEwJVUzEdMBsGA1UEChMU
# U3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFudGVjIFRpbWUgU3Rh
# bXBpbmcgU2VydmljZXMgQ0EgLSBHMgIQDs/0OMj+vzVuBNhqmBsaUDAJBgUrDgMC
# GgUAoF0wGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MTkwNzA0MTQwNjA5WjAjBgkqhkiG9w0BCQQxFgQUgxTrjxIQB/ugFl0PVk62xp40
# ICkwDQYJKoZIhvcNAQEBBQAEggEAdcx1v+n7ZZnqPmfmRvxXDBiSB91X7y22me0A
# mvo4as0XLSKRnrwvAtjFdBSN7jbjPL0+fP5CsfgfCEzfLLxAPL3iLK+2mLi/Og6i
# F9wxefYP1toWnQSYsLtdp+nbWo2NBG3Y9gEM+vhqr4HQGds/CXpK4rBHQLNM/vKP
# ExBrBCAFubOmxU5u0F4vQg6xJuMSIndyXd5Wx2Duwaemv3+fmx/z6z+FGy3YTh4C
# TnH8TUueW+uxLK59SgXVBXntBzu6GQEjvMPjLfXXldg8b2rd8b5kz7DnKMgPihPn
# v8vFzAdA37d1fAiBstmL7qtjvV7Z7pWHmv/m7GcUuLN2mZKYLA==
# SIG # End signature block
