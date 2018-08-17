param(
    $instance = "",
    [ValidateSet('xp', 'xc')]
    $demoType,
    $adminUser = "admin",
    $adminPassword = "b"
)

$config = Get-Content -Raw -Path "$PSSCriptRoot\warmup-config.json" | ConvertFrom-Json
if ($instance -eq "") {
    $instanceName = $config.instanceName
}
else {
    $instanceName = $instance    
}
Write-Host $instanceName

Function Get-SitecoreSession {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$site,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$username,
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$password
    )

    # Login - to create web session with authorisation cookies
    $loginPage = ("https://{0}/sitecore/login" -f $site)
  
    $login = Invoke-WebRequest $loginPage -SessionVariable webSession
  
    $form = $login.forms[0]
    $form.fields["UserName"] = $username
    $form.fields["Password"] = $password
  
    Write-Host ""
    Write-Host "logging in"
  
    $request = Invoke-WebRequest -Uri $loginPage -WebSession $webSession -Method POST -Body $form | Out-Null
	$cookies = $websession.Cookies.GetCookies($loginPage)
	if ($cookies["sitecore_userticket"]){
        Write-Host "login done"
	    Write-Host ""
		$webSession
    }else{
        Write-Host "login failed" -ForegroundColor Red
        exit 2
    }
}

Function RequestPage {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$url,
        [Parameter(Mandatory = $true, Position = 1)]
        [object]$webSession
    )
    Write-Host $(Get-Date -Format HH:mm:ss.fff)
    Write-Host "requesting $url ..."
    try { 
		$request = Invoke-WebRequest $url -WebSession $webSession -TimeoutSec 60000
        Write-Host "Done" 
        return $true
	} 
	catch {
        $status = $_.Exception.Response.StatusCode.Value__
        if ($status -ne 200) {
            Write-Host ("ERROR Something went wrong while requesting {0} - Error {1}" -f $url,$status) -ForegroundColor Red
        }
		return $false
    }
	finally{
		Write-Host $(Get-Date -Format HH:mm:ss.fff)
        Write-Host ""
	}
}

$demoType = $demoType.ToLower()
$session = Get-SitecoreSession $instanceName ("sitecore\{0}" -f $adminUser) $adminPassword
$errors = 0

Write-Host "Warming up XP Demo" -ForegroundColor Green
foreach ($page in $config.urls.xp) {
	if (!$(RequestPage "https://$instanceName$($page.url)" $session)){
		$errors++
	}
}

if ($demoType -eq "xc") {
Write-Host "Warming up XC Demo" -ForegroundColor Green
    foreach ($page in $config.urls.xc) {
		if (!$(RequestPage "https://$instanceName$($page.url)" $session)){
			$errors++
		}
    }
}

if ($errors -eq 0){
	Write-Host "Warmup Complete" -ForegroundColor Green
}else{
	Write-Host "Warmup Complete With Errors" -ForegroundColor Red
	exit 1
}
