Function Replace-String {
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

Function Add-DatabaseUser {
	param(
		[Parameter(Mandatory)]
		[string] $SqlServer,
		[Parameter(Mandatory)]
		[string] $SqlAdminUser,
		[Parameter(Mandatory)]
		[string] $SqlAdminPassword,
		[Parameter(Mandatory)]
		[string] $Username,
		[Parameter(Mandatory)]
		[string] $UserPassword,
		[Parameter(Mandatory)]
		[string] $DatabasePrefix,
		[Parameter(Mandatory)]
		[string] $DatabaseSuffix,
		[Parameter(Mandatory)]
		[bool] $IsCoreUser
	)

	#Write-Host ("Adding {0} to {1}_{2} with password {3}" -f $UserName, $DatabasePrefix, $DatabaseSuffix, $UserPassword   )
	$sqlVariables = "DatabasePrefix = $DatabasePrefix", "DatabaseSuffix = $DatabaseSuffix", "UserName = $UserName", "Password = $UserPassword"
	$sqlFile = ""
	if ($IsCoreUser ) {
		$sqlFile = Join-Path (Resolve-Path "..\..") "\database\addcoredatabaseuser.sql"
	}
	else {
		$sqlFile = Join-Path (Resolve-Path "..\..") "\database\adddatabaseuser.sql"
	}
	#Write-Host "Sql File: $sqlFile"
	Invoke-Sqlcmd -Variable $sqlVariables -Username $SqlAdminUser -Password $SqlAdminPassword -ServerInstance $SqlServer -InputFile $sqlFile
}

Function Kill-DatabaseConnections {
	param(
		[Parameter(Mandatory)]
		[string] $SqlServer,
		[Parameter(Mandatory)]
		[string] $SqlAdminUser,
		[Parameter(Mandatory)]
		[string] $SqlAdminPassword,
		[Parameter(Mandatory)]
		[string] $DatabasePrefix,
		[Parameter(Mandatory)]
		[string] $DatabaseSuffix
	)

	#Write-Host ("Adding {0} to {1}_{2} with password {3}" -f $UserName, $DatabasePrefix, $DatabaseSuffix, $UserPassword   )
	$sqlVariables = "DatabasePrefix = $DatabasePrefix", "DatabaseSuffix = $DatabaseSuffix"
	$sqlFile = Join-Path (Resolve-Path "..\..") "\database\killdatabaseconnections.sql"

	#Write-Host "Sql File: $sqlFile"
	Invoke-Sqlcmd -Variable $sqlVariables -Username $SqlAdminUser -Password $SqlAdminPassword -ServerInstance $SqlServer -InputFile $sqlFile
}

Function Start-SitecoreSite {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Uri,
		[ValidateSet('get', 'post')]
		[string]$Action = 'get',
		[string]$ContentType,
		[hashtable]$Parameters,
		[int]$ExpectedStatusCode = 200,
		[int]$TimeoutSec = 60
	)

	Function CheckResponseStatus {
		param(
			[Parameter(Mandatory = $true)]
			[PSCustomObject]$Response,
			[Parameter(Mandatory = $true)]
			[int]$ExpectedResponseStatus
		)

		if ($Response.StatusCode -eq $ExpectedResponseStatus -or $Response.StatusCode -eq 503) {
			return $true
		}

		return $false
	}

	try {
		Write-Verbose "$Action request to $Uri"

		if ($PSCmdlet.ShouldProcess($Uri, "HTTP request")) {
			for ($i = 0; $i -lt 3; $i++) {
				$response = Invoke-WebRequest -Method $Action -Uri $Uri -ContentType $ContentType -Body $Parameters -UseBasicParsing -TimeoutSec $TimeoutSec
				Write-Verbose "Response code was '$($response.StatusCode)'"
				if (CheckResponseStatus -Response $response -ExpectedResponseStatus $ExpectedStatusCode) {
					return
				}
				Start-Sleep -Seconds 20

			}
			if (!(CheckResponseStatus -Response $response -ExpectedResponseStatus $ExpectedStatusCode)) {
				throw "HTTP request $Uri expected Response code $ExpectedStatusCode but returned $($response.StatusCode)"
			}
		}
	}
	catch [System.Net.WebException] {

		if ($null -eq $_.Exception.Response) {
			Write-Error $_
			return
		}

		Write-Verbose "Response code was '$($response.StatusCode)'"

		$responseStatusIsExpected = CheckResponseStatus -Response $_.Exception.Response -ExpectedResponseStatus $ExpectedStatusCode

		if (-not($responseStatusIsExpected)) {
			Write-Error -Message "HTTP request $Uri expected Response code $ExpectedStatusCode but returned $([int]$_.Exception.Response.StatusCode)"
		}
	}
	catch {
		Write-Error $_
	}
}

Function Get-ObjectMembers {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $True, ValueFromPipeline = $True)]
		[PSCustomObject]$obj
	)
	$obj | Get-Member -MemberType NoteProperty | ForEach-Object {
		$key = $_.Name
		[PSCustomObject]@{Key = $key; Value = $obj."$key" }
	}
}

Function Import-SitecoreInstallFramework {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $True)]
		[string]$version,
		[Parameter(Mandatory = $True)]
		[string]$repositoryName,
		[Parameter(Mandatory = $True)]
		[string]$repositoryUrl
	)

	$sifVersion = $version -replace "-beta[0-9]*$"

	if (Get-Module -Name SitecoreInstallFramework) {
		Write-Host "Unloading SIF"
		Remove-Module SitecoreInstallFramework -Force
	}

	if ((Get-PSRepository | Where-Object { $_.Name -eq $repositoryName }).count -eq 0) {
		Register-PSRepository -Name $repositoryName -SourceLocation $repositoryUrl -InstallationPolicy Trusted
	}

	if ($version -like "*beta*") {
		# always try to install latest version if a beta is specified
		Write-Host "*** Beta vesion of SIF specified. Forcing installation." -ForegroundColor Yellow
		Install-Module SitecoreInstallFramework -Repository $repositoryName -AllowPrerelease -AllowClobber -Force 
	}
	else {
		$module = Get-Module -ListAvailable -name SitecoreInstallFramework | Where-Object { $_.Version -eq "$sifVersion" } | Select-Object -First 1 -ExpandProperty Name
		if ($null -eq $module) {
			Install-Module SitecoreInstallFramework -Repository $repositoryName -Scope CurrentUser
		}
	}
	Write-Host "Loading SIF $sifVersion"
	Import-Module SitecoreInstallFramework -RequiredVersion $sifVersion -Global -Force
}
