Function Invoke-InstallModuleTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleFullPath,
        [Parameter(Mandatory = $true)]
        [string]$ModulesDirDst,
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl
    )

    Copy-Item $ModuleFullPath -destination $ModulesDirDst -force

    $moduleToInstall = Split-Path -Path $ModuleFullPath -Leaf -Resolve

    Write-Host "Installing module: " $moduleToInstall -ForegroundColor Green
    $urlInstallModules = $BaseUrl + "/InstallModules.aspx?modules=" + $moduleToInstall
    Write-Host $urlInstallModules
    Invoke-RestMethod $urlInstallModules -TimeoutSec 720
}

Function Invoke-CreateDefaultStorefrontTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,
        [Parameter(Mandatory = $false)]
        [string]$scriptName = "CreateDefaultStorefrontTenantAndSite",
        [Parameter(Mandatory = $false)]
        [string]$siteName = "",
        [Parameter(Mandatory = $true)]
        [string]$sitecoreUsername,
        [Parameter(Mandatory = $true)]
        [string]$sitecoreUserPassword
    )

    if ($siteName -ne "") {
        Write-Host "Restarting the website and application pool for $siteName ..." -ForegroundColor Green
        Import-Module WebAdministration

        Stop-WebSite $siteName

        if ((Get-WebAppPoolState $siteName).Value -ne 'Stopped') {
            Stop-WebAppPool -Name $siteName
        }

        Start-WebAppPool -Name $siteName
        Start-WebSite $siteName
        Write-Host "Restarting the website and application pool for $siteName complete..." -ForegroundColor Green
    }

    Write-Host "Creating the default storefront..." -ForegroundColor Green

    #Added Try catch to avoid deployment failure due to an issue in SPE 4.7.1 - Once fixed, we can remove this
    Try {
        $urlPowerShellScript = $BaseUrl + "/-/script/v2/master/$($scriptName)?user=$($sitecoreUsername)&password=$($sitecoreUserPassword)"
        Invoke-RestMethod $urlPowerShellScript -TimeoutSec 1200
    }
    Catch {
        $errorMessage = $_.Exception.Message
        Write-Host "Error occured: $errorMessage ..." -ForegroundColor Red
    }

    Write-Host "Creating the default storefront complete..." -ForegroundColor Green
}

Function Invoke-DisableConfigFilesTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigDir,
        [parameter(Mandatory = $true)]
        [string[]]$ConfigFileList
    )

    foreach ($configFileName in $ConfigFileList) {
        Write-Host "Disabling config file: $configFileName" -ForegroundColor Green
        $configFilePath = Join-Path $ConfigDir -ChildPath $configFileName
        $disabledFilePath = "$configFilePath.disabled"

        if (Test-Path $configFilePath) {
            Rename-Item -Path $configFilePath -NewName $disabledFilePath
            Write-Host "  successfully disabled $configFilePath"
        }
        else {
            Write-Host "  configuration file not found." -ForegroundColor Red
        }
    }
}

Function Invoke-EnableConfigFilesTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigDir,
        [parameter(Mandatory = $true)]
        [string[]]$ConfigFileList
    )

    foreach ($configFileName in $ConfigFileList) {
        Write-Host "Enabling config file: $configFileName" -ForegroundColor Green
        $configFilePath = Join-Path $ConfigDir -ChildPath $configFileName
        $disabledFilePath = "$configFilePath.disabled"
        $exampleFilePath = "$configFilePath.example"

        if (Test-Path $configFilePath) {
            Write-Host "  config file is already enabled..."
        }
        elseif (Test-Path $disabledFilePath) {
            Rename-Item -Path $disabledFilePath -NewName $configFileName
            Write-Host "  successfully enabled $disabledFilePath"
        }
        elseif (Test-Path $exampleFilePath) {
            Rename-Item -Path $exampleFilePath -NewName $configFileName
            Write-Host "  successfully enabled $exampleFilePath"
        }
        else {
            Write-Host "  configuration file not found." -ForegroundColor Red
        }
    }
}

Function Invoke-ExpandArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceZip,
        [parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    Expand-Archive $SourceZip -DestinationPath $DestinationPath -Force
}

Function Invoke-NewCommerceSignedCertificateTask {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param
    (
        [Parameter(Mandatory)]
        [ValidateScript( { $_.HasPrivateKey -eq $true })]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Signer,
        [ValidateScript( { $_.StartsWith("Cert:\", "CurrentCultureIgnoreCase") })]
        [ValidateScript( { Test-Path $_ -Type Container })]
        [string]$CertStoreLocation = 'Cert:\LocalMachine\My',
        [ValidateNotNullOrEmpty()]
        [string]$DnsName = '127.0.0.1',
        [ValidateNotNullOrEmpty()]
        [string]$FriendlyName = "Sitecore Commerce Services SSL Certificate",
        [ValidateScript( { Test-Path $_ -Type Container })]
        [string]$Path,
        [string]$Name = 'localhost'
    )
    Write-Host "Creating self-signed certificate for $Name" -ForegroundColor Yellow
    $params = @{
        CertStoreLocation = $CertStoreLocation.Split('\')[1]
        DnsNames          = $DnsName
        FriendlyName      = $FriendlyName
        Signer            = $Signer
    }
    # Get or create self-signed certificate for localhost
    $certificates = Get-ChildItem -Path $CertStoreLocation -DnsName $DnsName | Where-Object { $_.FriendlyName -eq $FriendlyName }
    if ($certificates.Length -eq 0) {
        Write-Host "Create new self-signed certificate"
        NewCertificate @params
    }
    else {
        Write-Host "Reuse existing self-signed certificate"
    }
    Write-Host "Created self-signed certificate for $Name" -ForegroundColor Green
}

# This function is a complete copy from SIF/Private/Certificates.ps1 and should be removed together with Invoke-NewCommerceSignedCertificateTask later.
function NewCertificate {
    param(
        [string]$FriendlyName = "Sitecore Install Framework",
        [string[]]$DNSNames = "127.0.0.1",
        [ValidateSet("LocalMachine", "CurrentUser")]
        [string]$CertStoreLocation = "LocalMachine",
        [ValidateScript( { $_.HasPrivateKey })]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Signer
    )
    # DCOM errors in System Logs are by design.
    # https://support.microsoft.com/en-gb/help/4022522/dcom-event-id-10016-is-logged-in-windows-10-and-windows-server-2016
    $date = Get-Date
    $certificateLocation = "Cert:\\$CertStoreLocation\My"
    $rootCertificateLocation = "Cert:\\$CertStoreLocation\Root"
    # Certificate Creation Location.
    $location = @{ }
    if ($CertStoreLocation -eq "LocalMachine") {
        $location.MachineContext = $true
        $location.Value = 2 # Machine Context
    }
    else {
        $location.MachineContext = $false
        $location.Value = 1 # User Context
    }
    # RSA Object
    $rsa = New-Object -ComObject X509Enrollment.CObjectId
    $rsa.InitializeFromValue(([Security.Cryptography.Oid]"RSA").Value)
    # SHA256 Object
    $sha256 = New-Object -ComObject X509Enrollment.CObjectId
    $sha256.InitializeFromValue(([Security.Cryptography.Oid]"SHA256").Value)
    # Subject
    $subject = "CN=$($DNSNames[0]), O=DO_NOT_TRUST, OU=Created by https://www.sitecore.com"
    $subjectDN = New-Object -ComObject X509Enrollment.CX500DistinguishedName
    $subjectDN.Encode($Subject, 0x0)
    # Subject Alternative Names
    $san = New-Object -ComObject X509Enrollment.CX509ExtensionAlternativeNames
    $names = New-Object -ComObject X509Enrollment.CAlternativeNames
    foreach ($sanName in $DNSNames) {
        $name = New-Object -ComObject X509Enrollment.CAlternativeName
        $name.InitializeFromString(3, $sanName)
        $names.Add($name)
    }
    $san.InitializeEncode($names)
    # Private Key
    $privateKey = New-Object -ComObject X509Enrollment.CX509PrivateKey
    $privateKey.ProviderName = "Microsoft Enhanced RSA and AES Cryptographic Provider"
    $privateKey.Length = 2048
    $privateKey.ExportPolicy = 1 # Allow Export
    $privateKey.KeySpec = 1
    $privateKey.Algorithm = $rsa
    $privateKey.MachineContext = $location.MachineContext
    $privateKey.Create()
    # Certificate Object
    $certificate = New-Object -ComObject X509Enrollment.CX509CertificateRequestCertificate
    $certificate.InitializeFromPrivateKey($location.Value, $privateKey, "")
    $certificate.Subject = $subjectDN
    $certificate.NotBefore = ($date).AddDays(-1)
    if ($Signer) {
        # WebServer Certificate
        # WebServer Extensions
        $usage = New-Object -ComObject X509Enrollment.CObjectIds
        $keys = '1.3.6.1.5.5.7.3.2', '1.3.6.1.5.5.7.3.1' #Client Authentication, Server Authentication
        foreach ($key in $keys) {
            $keyObj = New-Object -ComObject X509Enrollment.CObjectId
            $keyObj.InitializeFromValue($key)
            $usage.Add($keyObj)
        }
        $webserverEnhancedKeyUsage = New-Object -ComObject X509Enrollment.CX509ExtensionEnhancedKeyUsage
        $webserverEnhancedKeyUsage.InitializeEncode($usage)
        $webserverBasicKeyUsage = New-Object -ComObject X509Enrollment.CX509ExtensionKeyUsage
        $webserverBasicKeyUsage.InitializeEncode([Security.Cryptography.X509Certificates.X509KeyUsageFlags]"DataEncipherment")
        $webserverBasicKeyUsage.Critical = $true
        # Signing CA cert needs to be in MY Store to be read as we need the private key.
        Move-Item -Path $Signer.PsPath -Destination $certificateLocation -Confirm:$false
        $signerCertificate = New-Object -ComObject X509Enrollment.CSignerCertificate
        $signerCertificate.Initialize($location.MachineContext, 0, 0xc, $Signer.Thumbprint)
        # Return the signing CA cert to the original location.
        Move-Item -Path "$certificateLocation\$($Signer.PsChildName)" -Destination $Signer.PSParentPath -Confirm:$false
        # Set issuer to root CA.
        $issuer = New-Object -ComObject X509Enrollment.CX500DistinguishedName
        $issuer.Encode($signer.Issuer, 0)
        $certificate.Issuer = $issuer
        $certificate.SignerCertificate = $signerCertificate
        $certificate.NotAfter = ($date).AddDays(36500)
        $certificate.X509Extensions.Add($webserverEnhancedKeyUsage)
        $certificate.X509Extensions.Add($webserverBasicKeyUsage)
    }
    else {
        # Root CA
        # CA Extensions
        $rootEnhancedKeyUsage = New-Object -ComObject X509Enrollment.CX509ExtensionKeyUsage
        $rootEnhancedKeyUsage.InitializeEncode([Security.Cryptography.X509Certificates.X509KeyUsageFlags]"DigitalSignature,KeyEncipherment,KeyCertSign")
        $rootEnhancedKeyUsage.Critical = $true
        $basicConstraints = New-Object -ComObject X509Enrollment.CX509ExtensionBasicConstraints
        $basicConstraints.InitializeEncode($true, -1)
        $basicConstraints.Critical = $true
        $certificate.Issuer = $subjectDN #Same as subject for root CA
        $certificate.NotAfter = ($date).AddDays(36500)
        $certificate.X509Extensions.Add($rootEnhancedKeyUsage)
        $certificate.X509Extensions.Add($basicConstraints)
    }
    $certificate.X509Extensions.Add($san) # Add SANs to Certificate
    $certificate.SignatureInformation.HashAlgorithm = $sha256
    $certificate.AlternateSignatureAlgorithm = $false
    $certificate.Encode()
    # Insert Certificate into Store
    $enroll = New-Object -ComObject X509Enrollment.CX509enrollment
    $enroll.CertificateFriendlyName = $FriendlyName
    $enroll.InitializeFromRequest($certificate)
    $certificateData = $enroll.CreateRequest(1)
    $enroll.InstallResponse(2, $certificateData, 1, "")
    # Retrieve thumbprint from $certificateData
    $certificateByteData = [System.Convert]::FromBase64String($certificateData)
    $createdCertificate = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2
    $createdCertificate.Import($certificateByteData)
    # Locate newly created certificate.
    $newCertificate = Get-ChildItem -Path $certificateLocation | Where-Object { $_.Thumbprint -Like $createdCertificate.Thumbprint }
    # Move CA to root store.
    if (!$Signer) {
        Move-Item -Path $newCertificate.PSPath -Destination $rootCertificateLocation
        $newCertificate = Get-ChildItem -Path $rootCertificateLocation | Where-Object { $_.Thumbprint -Like $createdCertificate.Thumbprint }
    }
    return $newCertificate
}

Function Invoke-OpenConnectionTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnString
    )

    try {
        $global:SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $global:SqlConnection.ConnectionString = $ConnString
        $global:SqlConnection.Open()
        $global:SqlTransaction = $global:SqlConnection.BeginTransaction()
    }
    catch {
        Write-Host "An error happened in OpenConnection, transaction will be rollbacked..." -ForegroundColor Red
        $global:SqlTransaction.Rollback()
        foreach ( $errorRecord in $Error ) {
            Write-Host -Object $errorRecord -ForegroundColor Red
            Write-Host -Object $errorRecord.InvocationInfo.PositionMessage -ForegroundColor Red
        }
    }
}

Function Invoke-CloseConnectionTask {
    $global:SqlTransaction.Commit();
    $global:SqlConnection.Close();
}

Function Invoke-CreateRoleTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnString,
        [Parameter(Mandatory = $true)]
        [string]$RoleName,
        [string]$ApplicationName = "sitecore"
    )

    Write-Host "Create Role $RoleName" -ForegroundColor Green
    try {
        Invoke-OpenConnectionTask $ConnString

        $SqlCommand = $global:SqlConnection.CreateCommand()
        $SqlCommand.Transaction = $global:SqlTransaction
        $SqlCommand.CommandText = "[dbo].[aspnet_Roles_CreateRole]"
        $SqlCommand.CommandType = [System.Data.CommandType]::StoredProcedure
        $SqlCommand.Parameters.AddWithValue("@ApplicationName", $ApplicationName) | Out-Null
        $SqlCommand.Parameters.AddWithValue("@RoleName", $RoleName) | Out-Null
        $SqlCommand.ExecuteNonQuery()
    }
    catch {
        Write-Host "An error happened, transaction will be rollbacked..." -ForegroundColor Red
        $global:SqlTransaction.Rollback()
        foreach ( $errorRecord in $Error ) {
            Write-Host -Object $errorRecord -ForegroundColor Red
            Write-Host -Object $errorRecord.InvocationInfo.PositionMessage -ForegroundColor Red
        }
    }
    finally {
        Invoke-CloseConnectionTask
    }
}

Function Invoke-AddRolesToUserTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnString,
        [Parameter(Mandatory = $true)]
        [string]$UserName,
        [Parameter(Mandatory = $true)]
        [string]$RoleNames,
        [string]$ApplicationName = "sitecore"
    )

    Write-Host "Add user $UserName to roles $RoleNames" -ForegroundColor Green
    try {
        Invoke-OpenConnectionTask $ConnString

        $SqlCommand = $global:SqlConnection.CreateCommand()
        $SqlCommand.Transaction = $global:SqlTransaction
        $SqlCommand.CommandText = "[dbo].[aspnet_UsersInRoles_AddUsersToRoles]"
        $SqlCommand.CommandType = [System.Data.CommandType]::StoredProcedure
        $SqlCommand.Parameters.AddWithValue("@ApplicationName", $ApplicationName) | Out-Null
        $SqlCommand.Parameters.AddWithValue("@UserNames", $UserName) | Out-Null
        $SqlCommand.Parameters.AddWithValue("@RoleNames", $RoleNames) | Out-Null
        $SqlCommand.Parameters.AddWithValue("@CurrentTimeUtc", (Get-Date)) | Out-Null
        $SqlCommand.ExecuteNonQuery();
    }
    catch {
        Write-Host "An error happened, transaction will be rollbacked..." -ForegroundColor Red
        $global:SqlTransaction.Rollback()
        foreach ( $errorRecord in $Error ) {
            Write-Host -Object $errorRecord -ForegroundColor Red
            Write-Host -Object $errorRecord.InvocationInfo.PositionMessage -ForegroundColor Red
        }
    }
    finally {
        Invoke-CloseConnectionTask
    }
}

Function Invoke-AddRoleToRoleTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnString,
        [Parameter(Mandatory = $true)]
        [string]$MemberRoleName,
        [Parameter(Mandatory = $true)]
        [string]$TargetRoleName,
        [string]$ApplicationName = ""
    )

    Write-Host "Add member role $MemberRoleName to target role $TargetRoleName" -ForegroundColor Green
    try {
        Invoke-OpenConnectionTask $ConnString

        $SqlCommand = $global:SqlConnection.CreateCommand()
        $SqlCommand.Transaction = $global:SqlTransaction
        $SqlCommand.CommandText = "INSERT INTO RolesInRoles (MemberRoleName, TargetRoleName, ApplicationName, Created) VALUES (@MemberRoleName, @TargetRoleName, @ApplicationName, @CurrentTimeUtc)"
        $SqlCommand.Parameters.AddWithValue("@MemberRoleName", $MemberRoleName) | Out-Null
        $SqlCommand.Parameters.AddWithValue("@TargetRoleName", $TargetRoleName) | Out-Null
        $SqlCommand.Parameters.AddWithValue("@ApplicationName", $ApplicationName) | Out-Null
        $SqlCommand.Parameters.AddWithValue("@CurrentTimeUtc", (Get-Date)) | Out-Null
        $SqlCommand.ExecuteNonQuery()
    }
    catch {
        Write-Host "An error happened, transaction will be rollbacked..." -ForegroundColor Red
        $global:SqlTransaction.Rollback()
        foreach ( $errorRecord in $Error ) {
            Write-Host -Object $errorRecord -ForegroundColor Red
            Write-Host -Object $errorRecord.InvocationInfo.PositionMessage -ForegroundColor Red
        }
    }
    finally {
        Invoke-CloseConnectionTask
    }
}

Function Invoke-ClearRedisTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RedisInstallationPath,
        [Parameter(Mandatory = $true)]
        [string[]]$EnvironmentsGuids
    )

    $redisCli = "$RedisInstallationPath\redis-cli.exe"

    foreach ($envGuid in $EnvironmentsGuids) {
        Write-Host "Clean Redis * $envGuid *" -ForegroundColor Green
        & $redisCli KEYS "*$envGuid*" | ForEach-Object { & $redisCli DEL $_ }
    }
}

Register-SitecoreInstallExtension -Command Invoke-NewCommerceSignedCertificateTask -As NewCommerceSignedCertificate -Type Task -Force
Register-SitecoreInstallExtension -Command Invoke-InstallModuleTask -As InstallModule -Type Task -Force
Register-SitecoreInstallExtension -Command Invoke-EnableConfigFilesTask -As EnableConfigFiles -Type Task -Force
Register-SitecoreInstallExtension -Command Invoke-DisableConfigFilesTask -As DisableConfigFiles -Type Task -Force
Register-SitecoreInstallExtension -Command Invoke-CreateDefaultStorefrontTask -As CreateDefaultStorefront -Type Task -Force
Register-SitecoreInstallExtension -Command Invoke-ExpandArchive -As ExpandArchive -Type Task -Force
Register-SitecoreInstallExtension -Command Invoke-OpenConnectionTask -As OpenConnection -Type Task -Force
Register-SitecoreInstallExtension -Command Invoke-CloseConnectionTask -As CloseConnection -Type Task -Force
Register-SitecoreInstallExtension -Command Invoke-CreateRoleTask -As CreateRole -Type Task -Force
Register-SitecoreInstallExtension -Command Invoke-AddRolesToUserTask -As AddRolesToUser -Type Task -Force
Register-SitecoreInstallExtension -Command Invoke-AddRoleToRoleTask -As AddRoleToRole -Type Task -Force
Register-SitecoreInstallExtension -Command Invoke-ClearRedisTask -As ClearRedis -Type Task -Force
# SIG # Begin signature block
# MIIXwQYJKoZIhvcNAQcCoIIXsjCCF64CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUK9PwpRi7w5SrXbdkXfyuPvD7
# FUegghL8MIID7jCCA1egAwIBAgIQfpPr+3zGTlnqS5p31Ab8OzANBgkqhkiG9w0B
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
# MAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFEccAKLqzLAFirs9JutGMPcn
# UaNfMA0GCSqGSIb3DQEBAQUABIIBAB6YVJaVej86LjJaeu9bsdGeGlMHEKy56MvZ
# CGXNUp7IXQ2IBUyl3YdrJaI6If5Bb5TM5k/WPpeCHX8rsfM3Td/UY42nDVF3hWgH
# nPb9kTsEaUio8MTlgCn7LWic63AD8IOScKKWliWxS8TAp35Iau1IZG2yOZZbSMBP
# 6/f1lUpqWV7jMXegEoChHd6xB8PoOB6IT/h3LwJHOM2AhpQ4/mzKjLSfSD1Gj5pe
# XQuTtZT91M2nv5s68P9u8xTmh4Jy2IwUbPXuJY6T/iz7adw7VHmdK8RbzdYqeDfV
# dA8/JdG8FH1C3mspoFSGFdMDuzRzpcLPKHcsF5ZVsMFi3yvZDCehggILMIICBwYJ
# KoZIhvcNAQkGMYIB+DCCAfQCAQEwcjBeMQswCQYDVQQGEwJVUzEdMBsGA1UEChMU
# U3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFudGVjIFRpbWUgU3Rh
# bXBpbmcgU2VydmljZXMgQ0EgLSBHMgIQDs/0OMj+vzVuBNhqmBsaUDAJBgUrDgMC
# GgUAoF0wGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MTkwNzA1MTgzMzIyWjAjBgkqhkiG9w0BCQQxFgQUZDhGUy3M+fDBFgF0N7J/snM2
# PdUwDQYJKoZIhvcNAQEBBQAEggEAcJg4hgtbO7MafJsSPQzkAstfkxTMCt1cU0lW
# lTlLMe6KStF8PYkPaiSGSED7NxbuAy478X0eH/gmpCd+L7jUiSYlqE35R16H02UT
# IT/jG/Ed9olhd9mWLe/nAy3yUbaDueYcyznIFrTnJjR0kwhk0Sb6tElOz76UNwSc
# rHKmzXg0FY19313/3bwgtG1ltrWuO7wOik6Xb+yJP0ljz4WWVospmgkQlZ0Fo+5P
# m2rfPvKcZPuLmjgqjMJu87rFYsWiS/YWwqCrME03Jj2Kt36qkxtaO5qb6PHBmz2w
# aEz0Sc/whRjRWxkQbZT2TUm+4Wr8AcLOw2lKC/5a0gc1Sa4sCw==
# SIG # End signature block
