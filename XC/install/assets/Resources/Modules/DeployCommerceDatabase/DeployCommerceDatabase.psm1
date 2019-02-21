
function Invoke-DeployCommerceDatabaseTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CommerceServicesDbServer,
        [Parameter(Mandatory=$true)]
        [string]$CommerceServicesDbName,
        [Parameter(Mandatory=$true)]
        [string]$CommerceServicesGlobalDbName,
        [Parameter(Mandatory=$true)]
        [string]$CommerceEngineDacPac,
        [Parameter(Mandatory=$true)]
        [string]$UserName
    )

    #************************************************************************
    #***** DEPLOY DATABASE DACPACS ****
    #************************************************************************
    #Drop the CommerceServices databases if they exist
    Write-Host "Deleting existing CommerceServices databases...";
    Add-SQLPSSnapin;
    DropSQLDatabase $CommerceServicesDbName
    DropSQLDatabase $CommerceServicesGlobalDbName

    Write-Host "Creating CommerceServices databases...";
    $connectionString = "Server=" + $CommerceServicesDbServer + ";Trusted_Connection=Yes;"

    #deploy using the dacpac
    try {
        deploydacpac $CommerceEngineDacPac $connectionString $CommerceServicesGlobalDbName
        deploydacpac $CommerceEngineDacPac $connectionString $CommerceServicesDbName
        write-host "adding roles to commerceservices databases...";
        AddSqlUserToRole $CommerceServicesDbServer $CommerceServicesGlobalDbName $UserName "db_owner"
        AddSqlUserToRole $CommerceServicesDbServer $CommerceServicesDbName $UserName "db_owner"
    }
    catch {
        Write-Host $_.Exception
        Write-Error $_ -ErrorAction Continue
        $dacpacError = $TRUE
    }
}

function Invoke-AddCommerceUserToCoreDatabaseTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SitecoreDbServer,
        [Parameter(Mandatory=$true)]
        [string]$SitecoreCoreDbName,
        [Parameter(Mandatory=$true)]
        [string]$UserName
    )

    #************************************************************************
    #***** Grant Sitecore Core database permissions to Commerce User     ****
    #************************************************************************

    try {
        AddSqlUserToRole $SitecoreDbServer $SitecoreCoreDbName $UserName "db_owner"
    }
    catch {
        Write-Error $_ -ErrorAction Continue
    }
}

function Add-SQLPSSnapin
{
    #
    # Add the SQL Server Provider.
    #

    $ErrorActionPreference = "Stop";

    $shellIds = Get-ChildItem HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds;

    if(Test-Path -Path "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps") {
        $sqlpsreg = "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps"
    }
    elseif(Test-Path -Path "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps110") {
        try{
            if((Get-PSSnapin -Registered |? { $_.Name -ieq "SqlServerCmdletSnapin110"}).Count -eq 0) {

                Write-Host "Registering the SQL Server 2012 Powershell Snapin";

                if(Test-Path -Path $env:windir\Microsoft.NET\Framework\v4.0.30319\InstallUtil.exe) {
                    Set-Alias installutil $env:windir\Microsoft.NET\Framework\v4.0.30319\InstallUtil.exe;
                }
                elseif (Test-Path -Path $env:windir\Microsoft.NET\Framework\v2.0.50727\InstallUtil.exe) {
                    Set-Alias installutil $env:windir\Microsoft.NET\Framework\v2.0.50727\InstallUtil.exe;
                }
                else {
                    throw "InstallUtil wasn't found!";
                }

                if(Test-Path -Path "$env:ProgramFiles\Microsoft SQL Server\110\Tools\PowerShell\Modules\SQLPS\") {
                    installutil "$env:ProgramFiles\Microsoft SQL Server\110\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSProvider.dll";
                    installutil "$env:ProgramFiles\Microsoft SQL Server\110\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSSnapins.dll";
                }
                elseif(Test-Path -Path "${env:ProgramFiles(x86)}\Microsoft SQL Server\110\Tools\PowerShell\Modules\SQLPS\") {
                    installutil "${env:ProgramFiles(x86)}\Microsoft SQL Server\110\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSProvider.dll";
                    installutil "${env:ProgramFiles(x86)}\Microsoft SQL Server\110\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSSnapins.dll";
                }

                Add-PSSnapin SQLServer*110;
                Write-Host "Sql Server 2012 Powershell Snapin registered successfully.";
            }
        }catch{}

        $sqlpsreg = "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps110";
    }
    elseif(Test-Path -Path "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps120") {
        try{
            if((Get-PSSnapin -Registered |? { $_.Name -ieq "SqlServerCmdletSnapin120"}).Count -eq 0) {

                Write-Host "Registering the SQL Server 2014 Powershell Snapin";

                if(Test-Path -Path $env:windir\Microsoft.NET\Framework\v4.0.30319\InstallUtil.exe) {
                    Set-Alias installutil $env:windir\Microsoft.NET\Framework\v4.0.30319\InstallUtil.exe;
                }
                elseif (Test-Path -Path $env:windir\Microsoft.NET\Framework\v2.0.50727\InstallUtil.exe) {
                    Set-Alias installutil $env:windir\Microsoft.NET\Framework\v2.0.50727\InstallUtil.exe;
                }
                else {
                    throw "InstallUtil wasn't found!";
                }

                if(Test-Path -Path "$env:ProgramFiles\Microsoft SQL Server\120\Tools\PowerShell\Modules\SQLPS\") {
                    installutil "$env:ProgramFiles\Microsoft SQL Server\120\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSProvider.dll";
                    installutil "$env:ProgramFiles\Microsoft SQL Server\120\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSSnapins.dll";
                }
                elseif(Test-Path -Path "${env:ProgramFiles(x86)}\Microsoft SQL Server\120\Tools\PowerShell\Modules\SQLPS\") {
                    installutil "${env:ProgramFiles(x86)}\Microsoft SQL Server\120\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSProvider.dll";
                    installutil "${env:ProgramFiles(x86)}\Microsoft SQL Server\120\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSSnapins.dll";
                }

                Add-PSSnapin SQLServer*120;
                Write-Host "Sql Server 2014 Powershell Snapin registered successfully.";
            }
        }catch{}

        $sqlpsreg = "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps120";
    }
    elseif(Test-Path -Path "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps130") {
        try{
            if((Get-PSSnapin -Registered |? { $_.Name -ieq "SqlServerCmdletSnapin130"}).Count -eq 0) {

                Write-Host "Registering the SQL Server 2016 Powershell Snapin";

                if(Test-Path -Path $env:windir\Microsoft.NET\Framework\v4.0.30319\InstallUtil.exe) {
                    Set-Alias installutil $env:windir\Microsoft.NET\Framework\v4.0.30319\InstallUtil.exe;
                }
                elseif (Test-Path -Path $env:windir\Microsoft.NET\Framework\v2.0.50727\InstallUtil.exe) {
                    Set-Alias installutil $env:windir\Microsoft.NET\Framework\v2.0.50727\InstallUtil.exe;
                }
                else {
                    throw "InstallUtil wasn't found!";
                }

                if(Test-Path -Path "$env:ProgramFiles\Microsoft SQL Server\130\Tools\PowerShell\Modules\SQLPS\") {
                    installutil "$env:ProgramFiles\Microsoft SQL Server\130\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSProvider.dll";
                    installutil "$env:ProgramFiles\Microsoft SQL Server\130\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSSnapins.dll";
                }
                elseif(Test-Path -Path "${env:ProgramFiles(x86)}\Microsoft SQL Server\130\Tools\PowerShell\Modules\SQLPS\") {
                    installutil "${env:ProgramFiles(x86)}\Microsoft SQL Server\130\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSProvider.dll";
                    installutil "${env:ProgramFiles(x86)}\Microsoft SQL Server\130\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSSnapins.dll";
                }

                Add-PSSnapin SQLServer*130;
                Write-Host "Sql Server 2016 Powershell Snapin registered successfully.";
            }
        }catch{}

        $sqlpsreg = "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps130";
    }
    elseif(Test-Path -Path "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps140") { 
        try{
            if((Get-PSSnapin -Registered |? { $_.Name -ieq "SqlServerCmdletSnapin140"}).Count -eq 0) {
                Write-Host "Registering the SQL Server 2017 Powershell Snapin";
                if(Test-Path -Path $env:windir\Microsoft.NET\Framework\v4.0.30319\InstallUtil.exe) {
                    Set-Alias installutil $env:windir\Microsoft.NET\Framework\v4.0.30319\InstallUtil.exe;
                }
                elseif (Test-Path -Path $env:windir\Microsoft.NET\Framework\v2.0.50727\InstallUtil.exe) {
                    Set-Alias installutil $env:windir\Microsoft.NET\Framework\v2.0.50727\InstallUtil.exe;
                }
                else {
                    throw "InstallUtil wasn't found!";
                }
                if(Test-Path -Path "$env:ProgramFiles\Microsoft SQL Server\140\Tools\PowerShell\Modules\SQLPS\") {
                    installutil "$env:ProgramFiles\Microsoft SQL Server\140\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSProvider.dll";
                    installutil "$env:ProgramFiles\Microsoft SQL Server\140\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSSnapins.dll";
                }
                elseif(Test-Path -Path "${env:ProgramFiles(x86)}\Microsoft SQL Server\140\Tools\PowerShell\Modules\SQLPS\") {
                    installutil "${env:ProgramFiles(x86)}\Microsoft SQL Server\140\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSProvider.dll";
                    installutil "${env:ProgramFiles(x86)}\Microsoft SQL Server\140\Tools\PowerShell\Modules\SQLPS\Microsoft.SqlServer.Management.PSSnapins.dll"; 
                }

                Add-PSSnapin SQLServer*140;
                Write-Host "Sql Server 2017 Powershell Snapin registered successfully.";
            }
        }catch{}
        $sqlpsreg = "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.SqlServer.Management.PowerShell.sqlps140";
    }
    else {
        throw "SQL Server Provider for Windows PowerShell is not installed."
    }

    $item = Get-ItemProperty $sqlpsreg
    $sqlpsPath = [System.IO.Path]::GetDirectoryName($item.Path)

    #
    # Set mandatory variables for the SQL Server provider
    #
    Set-Variable -scope Global -name SqlServerMaximumChildItems -Value 0
    Set-Variable -scope Global -name SqlServerConnectionTimeout -Value 30
    Set-Variable -scope Global -name SqlServerIncludeSystemObjects -Value $false
    Set-Variable -scope Global -name SqlServerMaximumTabCompletion -Value 1000

    #
    # Load the snapins, type data, format data
    #
    Push-Location

    cd $sqlpsPath

    if (Get-PSSnapin -Registered | where {$_.name -eq 'SqlServerProviderSnapin100'})
    {
        if( !(Get-PSSnapin | where {$_.name -eq 'SqlServerProviderSnapin100'}))
        {
            Add-PSSnapin SqlServerProviderSnapin100;
        }

        if( !(Get-PSSnapin | where {$_.name -eq 'SqlServerCmdletSnapin100'}))
        {
            Add-PSSnapin SqlServerCmdletSnapin100;
        }

        Write-Host "Using the SQL Server 2008 Powershell Snapin.";

       Update-TypeData -PrependPath SQLProvider.Types.ps1xml -ErrorAction SilentlyContinue
       Update-FormatData -prependpath SQLProvider.Format.ps1xml -ErrorAction SilentlyContinue
    }
    else #Sql Server 2012 or 2014 module should be registered now.  Note, we'll only use it if the earlier version isn't installed.
    {
        if (!(Get-Module -ListAvailable -Name SqlServer))
        {
            Write-Host "Using the SQL Server 2012 or 2014 Powershell Module.";

            if( !(Get-Module | where {$_.name -eq 'sqlps'}))
            {
                Import-Module 'sqlps' -DisableNameChecking;
            }
            cd $sqlpsPath;
            cd ..\PowerShell\Modules\SQLPS;
        }

        Update-TypeData -PrependPath SQLProvider.Types.ps1xml -ErrorAction SilentlyContinue
        Update-FormatData -prependpath SQLProvider.Format.ps1xml -ErrorAction SilentlyContinue
    }

    Pop-Location
}

function DropSQLDatabase
{
    param
    (
        [String]$dbName=$(throw 'Parameter -dbName is missing!')
    )

    try
    {
        $server = new-object ("Microsoft.SqlServer.Management.Smo.Server")
        if($server.Databases.Contains($dbName))
        {
            Write-Host "Attemping to delete database $dbName" -ForegroundColor Green -NoNewline
            Invoke-Sqlcmd -Query "USE [master]; ALTER DATABASE [$($dbName)] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$($dbName)]"
            Write-Host "    DELETED" -ForegroundColor DarkGreen
        }
        else
        {
            Write-Warning "$dbName does not exist, cannot delete"
        }
    }
    catch
    {
	    Write-Host $_.Exception.Message
        Write-Host "    Unable to delete database $dbName" -ForegroundColor Red
    }
}

function AddSqlUserToRole
{
    param
    (
        [String]$dbServer=$(throw 'Parameter -dbServer is missing!'),
        [String]$dbName=$(throw 'Parameter -dbName is missing!'),
        [String]$userName=$(throw 'Parameter -userName is missing!'),
        [String]$role=$(throw 'Parameter -role is missing!')
    )
    Write-Host "Attempting to add the user $userName to database $dbName as role $role" -ForegroundColor Green -NoNewline

    try
    {
        Invoke-Sqlcmd -ServerInstance $dbServer -Query "IF NOT EXISTS (SELECT * FROM master.dbo.syslogins WHERE name = '$($userName)') BEGIN CREATE LOGIN [$($userName)] FROM WINDOWS WITH DEFAULT_DATABASE=[$($dbName)], DEFAULT_LANGUAGE=[us_english] END"
        Invoke-Sqlcmd -ServerInstance $dbServer -Query "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$($userName)') BEGIN USE [$($dbName)] CREATE USER [$($userName)] FOR LOGIN [$($userName)] END"
        Invoke-Sqlcmd -ServerInstance $dbServer -Query "USE [$($dbName)] EXEC sp_addrolemember '$($role)', '$($userName)'"
        Write-Host "     Added" -ForegroundColor DarkGreen
    }
    catch
    {
        Write-Host ""
        Write-Host "Error: Unable to add user $userName`nDetails: $_" -ForegroundColor Red
    }
}

function GetSqlDacVersion
{
    # load in DAC DLL (requires config file to support .NET 4.0)
    # change file location for a 32-bit OS
    # param out the base path of SQL Server
    $sqlServerVersions = @("140", "130", "120", "110");
    $sqlCurrentVersion = ""
    $baseSQLServerPath = "C:\Program Files (x86)\Microsoft SQL Server\{0}\DAC\bin\Microsoft.SqlServer.Dac.dll";

    foreach($sqlServerVersion in $sqlServerVersions)
    {
        $fullPath = $baseSQLServerPath -f $sqlServerVersion;

        if(Test-Path -Path $fullPath)
        {
            Write-Host "Using SQL Server $($sqlServerVersion) to import DACPAC";
            #add-type -path $fullPath;
            $sqlCurrentVersion = $sqlServerVersion
            break;
        }
    }

    return $sqlCurrentVersion
}


#************************************************************************
#**** DACPAC DEPLOY FUNCTION ****
#************************************************************************

function DeployDacpac
(
    [Parameter(Mandatory=$true)][string]$dacpac,
    [Parameter(Mandatory=$true)]$connStr,
    [Parameter(Mandatory=$true)]$databaseName
)
{
    Write-Host "Importing DACPAC $($dacpac)"

    # load in DAC DLL (requires config file to support .NET 4.0)
    # change file location for a 32-bit OS
    # param out the base path of SQL Server
    $sqlServerVersions = @("140", "130", "120", "110");
    $sqlCurrentVersion = ""
    $baseSQLServerPath = "C:\Program Files (x86)\Microsoft SQL Server\{0}\DAC\bin\Microsoft.SqlServer.Dac.dll";

    foreach($sqlServerVersion in $sqlServerVersions)
    {
        $fullPath = $baseSQLServerPath -f $sqlServerVersion;

        if(Test-Path -Path $fullPath)
        {
            Write-Host "Using SQL Server $($sqlServerVersion) to import DACPAC";
            add-type -path $fullPath;
            $sqlCurrentVersion = $sqlServerVersion
            break;
        }
    }

    if($sqlCurrentVersion -match "110")
    {
        Write-Error "Cannot deploy this dacpac with the version Sql 2012, please upgrade your version or use the sql script located in the same location as the dacpac"
        return;
    }

    # make DacServices object, needs a connection string
    $d = new-object Microsoft.SqlServer.Dac.DacServices $connStr;

    # register events, if you want 'em
    register-objectevent -in $d -eventname Message -source "msg" -action { out-host -in $Event.SourceArgs[1].Message.Message }

    # Load dacpac from file & deploy to database named $databaseName
     $dp = [Microsoft.SqlServer.Dac.DacPackage]::Load($dacpac)
     $d.deploy($dp, $databaseName, $TRUE);

    # clean up event
    unregister-event -source "msg";
}

Register-SitecoreInstallExtension -Command Invoke-DeployCommerceDatabaseTask -As DeployCommerceDatabase -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-AddCommerceUserToCoreDatabaseTask -As AddCommerceUserToCoreDatabase -Type Task -Force
# SIG # Begin signature block
# MIIXwQYJKoZIhvcNAQcCoIIXsjCCF64CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUmUPgj/GJpY9v2K1Ay4CSvuSv
# vbWgghL8MIID7jCCA1egAwIBAgIQfpPr+3zGTlnqS5p31Ab8OzANBgkqhkiG9w0B
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
# MAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFF2Im/TilbXaBywjzxfT98Fa
# qpydMA0GCSqGSIb3DQEBAQUABIIBAFC4cNXSsrpQ/w7ptjJZgpmEyOxvYQpou8qy
# ce0Wqbv4kTE+bwiIXiQJ0eollrer7Sllrcjtnpeu3rjoX3HTEAcClSch9ZHmMfwL
# rkeDyTmLWOAF3RIsitKFrcZSlutGTw4Y/ZG2/l7GL020kT87bJomvUZ0J5jOcA1E
# t+dUOxXqxjEdYIyXxvMG+hjs8A6XmaeCNyvWqgsFyOTdwGFGsqXjA5B6xgfVnEgM
# EbbxmGPLvBKOw4dAUrT+FFMr0fQnEWp1nsd7AlNddFZaNmsT23mt7HRp3uBMqEG6
# WikQEmJr4LJz4WJI3WDYXvrWYmMJn+k9K4tXyioVrKQFoNsRJSmhggILMIICBwYJ
# KoZIhvcNAQkGMYIB+DCCAfQCAQEwcjBeMQswCQYDVQQGEwJVUzEdMBsGA1UEChMU
# U3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFudGVjIFRpbWUgU3Rh
# bXBpbmcgU2VydmljZXMgQ0EgLSBHMgIQDs/0OMj+vzVuBNhqmBsaUDAJBgUrDgMC
# GgUAoF0wGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MTkwMjE4MjEwODAxWjAjBgkqhkiG9w0BCQQxFgQUh+r9g0gY+ZSfGhgKII6yhQSu
# OPYwDQYJKoZIhvcNAQEBBQAEggEAJZu7OT5ye5thJa+iv8rXKmrXQLXB2rHBBPxz
# OpcRHUh4bbXKPCAUaCTSh4ppJDULgLRBzu+ElQ6Ih+t0wE5DacRY2sgo73AU5Z9r
# tymiSZXOoX38EIP6qU9GrJmMn4ZwUDvprK7tt/rPAixVPJFLqDPfvqlXEdYKisBQ
# gebPKuXpCC624Kquzuvcdx5rsHleOkvtaYiAbH2oI7wIc/Q7M6V2DtWxB+7bT12j
# 3v3xKDZYMfwXnxz5Uh5c6fhimQJ/KNKBZGTLz0BM2Ynn+q52aECVOnuOXgAwwDBm
# gRuIWqSGzuiMaSDNWjPujju9VW7WptDHim1W7LeY2gIV6ka2gg==
# SIG # End signature block
