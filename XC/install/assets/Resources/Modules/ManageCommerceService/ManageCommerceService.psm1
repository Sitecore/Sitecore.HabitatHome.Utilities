#Requires -Modules WebAdministration

#Set-StrictMode -Version 2.0

Function Invoke-ManageCommerceServiceTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,		
        [Parameter(Mandatory = $true)]
        [ValidateSet('Remove-Website', 'Remove-WebAppPool', 'Remove-Item', 'Create-WebAppPool', 'Create-Website')]
        [string]$Action,
        [Parameter(Mandatory = $false)]
        [string]$PhysicalPath,
        [Parameter(Mandatory = $false)]
        [psobject[]]$UserAccount,
        [Parameter(Mandatory = $false)]
        [string]$AppPoolName = $Name,
        [Parameter(Mandatory = $false)]
        [string]$Port,
        [Parameter(Mandatory = $false)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2] $Signer
    )   

    Write-TaskInfo -Message $Name -Tag $Action   

    try {
        if ($PSCmdlet.ShouldProcess($Name, $Action)) {
            switch ($Action) {
                'Remove-Website' {                    
                    if (Get-Website($Name)) {
                        Write-Host "Removing Website '$Name'"
                        Remove-Website -Name $Name
                    }
                }
                'Remove-WebAppPool' {
                    if (Test-Path "IIS:\AppPools\$Name") {
                        if ((Get-WebAppPoolState $Name).Value -eq "Started") {
                            Write-Host "Stopping '$Name' application pool"
                            Stop-WebAppPool -Name $Name
                        }
                        Write-Host "Removing '$Name' application pool"
                        Remove-WebAppPool -Name $Name
                    }
                }
                'Remove-Item' {
                    if (Test-Path $PhysicalPath) {
                        Write-Host "Attempting to delete site directory '$PhysicalPath'"
                        Remove-Item $PhysicalPath -Recurse -Force
                        Write-Host "'$PhysicalPath' deleted" -ForegroundColor Green
                        dev_reset_iis_sql
                    }
                    else {
                        Write-Warning "'$PhysicalPath' does not exist, no need to delete"
                    }
                }
                'Create-WebAppPool' {				
                    Write-Host "Creating and starting the $Name Services application pool" -ForegroundColor Yellow
                    if ($Name -match "CommerceMinions") {
                        # ProductType of 1 is client OS
                        if ((Get-WmiObject Win32_OperatingSystem).ProductType -eq 1) {
                            Enable-WindowsOptionalFeature -Online -FeatureName IIS-ApplicationInit
                        }
                        else {
							if (!(Get-module ServerManager )) { 
								Import-Module ServerManager
							}
                            Install-WindowsFeature -Name Web-AppInit
                        }
                    }
                    $appPoolInstance = New-WebAppPool -Name $Name

                    if ($UserAccount -ne $null) {
                        $appPoolInstance.processModel.identityType = 3;
                        $appPoolInstance.processModel.userName = "$($UserAccount.domain)\$($UserAccount.username)";
                        $appPoolInstance.processModel.password = $UserAccount.password;
                        if ($Name -match "CommerceMinions") {
                            $appPoolInstance.startmode = 'alwaysrunning';
                            $appPoolInstance.autostart = $true;
                        }
                        $appPoolInstance | Set-Item;
                    }

                    $appPoolInstance.managedPipelineMode = "Integrated";
                    $appPoolInstance.managedRuntimeVersion = "";
                    $appPoolInstance | Set-Item
                    Start-WebAppPool -Name $Name
                    Write-Host "Creation of the $Name Services application pool completed" -ForegroundColor Green ;
                }
                'Create-Website' {
                    Write-Host "Creating and starting the $Name web site" -ForegroundColor Yellow
                    New-Website -Name $Name -ApplicationPool $AppPoolName -PhysicalPath $PhysicalPath
                    Write-Host "Creation and startup of the $Name Services web site completed" -ForegroundColor Green
                    
                    Write-Host "Creating self-signed certificate for $Name" -ForegroundColor Yellow                    
                    $params = @{
                        CertStoreLocation = "Cert:\LocalMachine\My"
                        DnsName           = "localhost"
                        Type              = 'SSLServerAuthentication'
                        Signer            = $Signer
                        FriendlyName      = "Sitecore Commerce Services SSL Certificate"
                        KeyExportPolicy   = 'Exportable'
                        KeyProtection     = 'None'
                        Provider          = 'Microsoft Enhanced RSA and AES Cryptographic Provider'
                    }
                    
                    # Get or create self-signed certificate for localhost                                        
                    $certificates = Get-ChildItem -Path $params.CertStoreLocation -DnsName $params.DnsName | Where-Object { $_.FriendlyName -eq $params.FriendlyName }
                    if ($certificates.Length -eq 0) {
                        Write-Host "Create new self-signed certificate"
                        $certificate = New-SelfSignedCertificate @params
                    }
                    else {
                        Write-Host "Reuse existing self-signed certificate"
                        $certificate = $certificates[0]
                    }
                    Write-Host "Created self-signed certificate for $Name" -ForegroundColor Green
                    
                    # Remove HTTP binding
                    Write-Host "Removing default HTTP binding" -ForegroundColor Yellow                    
                    Remove-WebBinding -Name $Name -Protocol "http"
                    Write-Host "Removed default HTTP binding" -ForegroundColor Green

                    # Create HTTPS binding
                    Write-Host "Adding HTTPS binding" -ForegroundColor Yellow
                    New-WebBinding -Name $Name -HostHeader $params.DnsName -Protocol "https" -SslFlags 1 -Port $Port
                    Write-Host "Added HTTPS binding" -ForegroundColor Green

                    # Associate SSL certificate with binding
                    Write-Host "Associating SSL certificate with site" -ForegroundColor Yellow
                    $binding = Get-WebBinding -Name $Name -HostHeader $params.DnsName -Protocol "https"
                    $binding.AddSslCertificate($certificate.GetCertHashString(), "My")
                    Write-Host "Associated SSL certificate with site" -ForegroundColor Green

                    # Start the site
                    Write-Host "Starting site" -ForegroundColor Yellow
                    $started = $false
                    $attempts = 1;
                    $retries = 5;

                    while ((-not $started) -and ($attempts -le $retries)) {
                        try {
                            $path = "IIS:\Sites\$Name"

                            if (Test-Path $path) {
                                $site = Get-Item $path

                                if ($Name -match "CommerceMinions") {
                                    $site | Set-ItemProperty -Name applicationDefaults.preloadEnabled -Value True
                                }

                                $site.Start()
                                
                                $started = $true
                            }                
                            else {
                                Write-Host "The site $Name does not exist"
                            }            
                        }
                        catch {
                            $attempts++
                            Write-Host "Unable to start the site $Name" -ForegroundColor Red                            
                            Start-Sleep -Seconds 5
                        }
                    }
                    Write-Host "Started site" -ForegroundColor Green
                }
            }
        }
    }
    catch {
        Write-Error $_
    }
}

Function Invoke-IssuingCertificateTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CertificateDnsName,
        [Parameter(Mandatory = $true)]
        [string]$CertificatePassword,
        [Parameter(Mandatory = $true)]
        [string]$CertificateStore,
        [Parameter(Mandatory = $true)]
        [string]$CertificateFriendlyName,
        [Parameter(Mandatory = $true)]
        [string]$IDServerPath        
    )

    $certificates = Get-ChildItem `
        -Path $CertificateStore `
        -DnsName $CertificateDnsName | Where-Object { $_.FriendlyName -eq $CertificateFriendlyName }

    if ($Certificates.Length -eq 0) {
        Write-Host "Issuing new certificate"

        $certificate = New-SelfSignedCertificate `
            -Subject $CertificateDnsName `
            -DnsName $CertificateDnsName `
            -KeyAlgorithm RSA `
            -KeyLength 2048 `
            -NotBefore (Get-Date) `
            -NotAfter (Get-Date).AddYears(1) `
            -CertStoreLocation $CertificateStore `
            -FriendlyName $CertificateFriendlyName `
            -HashAlgorithm SHA256 `
            -KeyUsage DigitalSignature, KeyEncipherment, DataEncipherment `
            -KeySpec Signature `
            -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")

            $certificatePath = $CertificateStore + "\" + $certificate.Thumbprint 
            $pfxPassword = ConvertTo-SecureString -String $CertificatePassword -Force -AsPlainText
            $pfxPath = ".\$CertificateDnsName.pfx"
            
            Write-Host "Exporting certificate"
            Export-PfxCertificate -Cert $certificatePath -FilePath $pfxPath -Password $pfxPassword
        
            Write-Host "Importing certificate"
            Import-PfxCertificate -FilePath $pfxPath -CertStoreLocation $CertificateStore -Password $pfxPassword -Exportable           
        
            Write-Host "Removing certificate files"
            Remove-Item $pfxPath
    }
    else {
        Write-Host "Found existing certificate"
        $certificate = $certificates[0]
    }

    Write-Host "Updating thumbprint in config file"
    $pathToJson = $(Join-Path -Path $IDServerPath -ChildPath "wwwroot\appsettings.json") 
    $originalJson = Get-Content $pathToJson -Raw | ConvertFrom-Json
    $settingsNode = $originalJson.AppSettings
    $settingsNode.IDServerCertificateThumbprint = $certificate.Thumbprint
    $originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $pathToJson
}

function Invoke-SetPermissionsTask {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_ })]
        [string]$Path,
        [psobject[]]$Rights
    )

    <#
        Rights should contains
        @{
            User
            FileSystemRights
            AccessControlType

            InheritanceFlags
            PropagationFlags
        }
    #>
   
    if(!$WhatIfPreference) {
        Get-Acl -Path $Path | Set-Acl -Path $Path
    }

    $acl = Get-Acl -Path $Path

    foreach($entry in $Rights){
        $user = "$($entry.User.domain)\$($entry.User.username)"
        $permissions = $entry.FileSystemRights
        $control = 'Allow'
        if($entry['AccessControlType']) { $control = $entry.AccessControlType }
        $inherit = 'ContainerInherit','ObjectInherit'
        if($entry['InheritanceFlags']) { $inherit = $entry.InheritanceFlags }
        $prop = 'None'
        if($entry['PropagationFlags']) { $prop = $entry.PropagationFlags }

        Write-TaskInfo -Message $user -Tag $control
        Write-TaskInfo -Message $path -Tag 'Path'
        Write-TaskInfo -Message $permissions -Tag 'Rights'
        Write-TaskInfo -Message $inherit -Tag 'Inherit'
        Write-TaskInfo -Message $prop -Tag 'Propagate'

        if($PSCmdlet.ShouldProcess($Path, "Setting permissions")) {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user, $permissions, $inherit, $prop, $control)
            $acl.SetAccessRule($rule)

            Write-Verbose "$control '$permissions' for user '$user' on '$path'"
            Write-Verbose "Permission inheritance: $inherit"
            Write-Verbose "Propagation: $prop"
            Set-Acl -Path $Path -AclObject $acl
            Write-Verbose "Permissions set"
        }
    }
}

Register-SitecoreInstallExtension -Command Invoke-ManageCommerceServiceTask -As ManageCommerceService -Type Task -Force
Register-SitecoreInstallExtension -Command Invoke-IssuingCertificateTask -As IssuingCertificate -Type Task -Force
Register-SitecoreInstallExtension -Command Invoke-SetPermissionsTask -As SetPermissions -Type Task -Force

function dev_reset_iis_sql {
    try {
        Write-Host "Restarting IIS"
        iisreset -stop
        iisreset -start
    }
    catch {
        Write-Host "Something went wrong restarting IIS again"
        iisreset -stop
        iisreset -start
    }

    $mssqlService = Get-Service *SQL* | Where-Object {$_.Status -eq 'Running' -and $_.DisplayName -like 'SQL Server (*'} | Select-Object -First 1 -ExpandProperty Name

    try {
        Write-Host "Restarting SQL Server"
        restart-service -force $mssqlService
    }
    catch {
        Write-Host "Something went wrong restarting SQL server again"
        restart-service -force $mssqlService
    }
}
