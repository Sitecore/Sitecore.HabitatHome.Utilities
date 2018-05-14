
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
        [psobject[]]$UserAccount = @()
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
	$userName = "$($UserAccount.domain)\$($UserAccount.username)"
	
	#deploy using the dacpac
	try {
		deploydacpac $CommerceEngineDacPac $connectionString $CommerceServicesGlobalDbName
		deploydacpac $CommerceEngineDacPac $connectionString $CommerceServicesDbName
		write-host "adding roles to commerceservices databases...";
		AddSqlUserToRole $CommerceServicesDbServer $CommerceServicesGlobalDbName $userName "db_owner"
		AddSqlUserToRole $CommerceServicesDbServer $CommerceServicesDbName $userName "db_owner"
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
        [psobject[]]$UserAccount = @()
    )

    #************************************************************************
	#***** Grant Sitecore Core database permissions to Commerce User     ****
	#************************************************************************
	
	$userName = "$($UserAccount.domain)\$($UserAccount.username)"
	
    try {
	    AddSqlUserToRole $SitecoreDbServer $SitecoreCoreDbName $userName "db_owner"
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
		    Invoke-Sqlcmd -Query "DROP DATABASE [$($dbName)]"
		    Write-Host "    DELETED" -ForegroundColor DarkGreen
        }
        else
        {
            Write-Warning "$dbName does not exist, cannot delete"
        }
	}
	catch
	{
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