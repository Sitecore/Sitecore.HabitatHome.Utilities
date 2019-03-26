param(
    [string]$instance,
    [ValidateSet('sitecore', 'xp', 'xc')]
    [string]$demoType,
    [string]$adminUser = 'admin',
    [string]$adminPassword = 'b'
)

$config = Get-Content -Raw -Path "$PSSCriptRoot\warmup-config.json" | ConvertFrom-Json
if ($instance -eq "") {
    $instanceName = $config.instanceName
}
else {
    $instanceName = $instance    
}
Write-Host $instanceName

function TestStatusCode {
    param($response)

    if ($response.StatusCode -ne 200) {
        throw "The request returned a non-200 status code [$($response.StatusCode)]"
    }
}

function TestCookie {
    param([System.Net.CookieContainer]$cookies)

    $discovered = @($cookies.GetCookies($site) |
            Where-Object { $_.Name -eq '.ASPXAUTH' -Or $_.Name -eq '.AspNet.Cookies' })

    if ($discovered.Count -ne 1) {
        throw "Authentication failed. Check username and password"
    }
}
Function Get-SitecoreSession {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$site,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]$username,
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$password
    )

    $uri = "$site/sitecore/login?fbc=1"
    $authResponse = Invoke-WebRequest -uri $uri -SessionVariable session -UseBasicParsing
    TestStatusCode $authResponse

    # Set login info
    $fields = @{}
    $authResponse.InputFields.ForEach( {
        
            $fields[$_.Name] = $_.Value
        
        })

    $fields.UserName = $Username
    $fields.Password = $Password

    # Login using the same session
    $authResponse = Invoke-WebRequest -uri $uri -WebSession $session -Method POST -Body $fields -UseBasicParsing
    TestStatusCode $authResponse
    TestCookie $session.Cookies

    return $session
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
            Write-Host ("ERROR Something went wrong while requesting {0} - Error {1}" -f $url, $status) -ForegroundColor Red
        }
        return $false
    }
    finally {
        Write-Host $(Get-Date -Format HH:mm:ss.fff)
        Write-Host ""
    }
}

$demoType = $demoType.ToLower()
$session = Get-SitecoreSession "https://$instanceName" ("sitecore\{0}" -f $adminUser) $adminPassword
$errors = 0

if ($demoType -eq "sitecore") {
    Write-Host "Warming up Sitecore" -ForegroundColor Green
    foreach ($page in $config.urls.sitecore) {
        if (!$(RequestPage "https://$instanceName$($page.url)" $session)) {
            $errors++
        }
    }
}

if ($demoType -eq ("xp" -or "xc")) {
    Write-Host "Warming up XP Demo" -ForegroundColor Green
    foreach ($page in $config.urls.sitecore) {
        if (!$(RequestPage "https://$instanceName$($page.url)" $session)) {
            $errors++
        }
    }
    foreach ($page in $config.urls.xp) {
        if (!$(RequestPage "https://$instanceName$($page.url)" $session)) {
            $errors++
        }
    }
}

if ($demoType -eq "xc") {
    Write-Host "Warming up XC Demo" -ForegroundColor Green
    foreach ($page in $config.urls.xc) {
        if (!$(RequestPage "https://$instanceName$($page.url)" $session)) {
            $errors++
        }
    }
}

if ($errors -eq 0) {
    Write-Host "Warmup Complete" -ForegroundColor Green
}
else {
    Write-Host "Warmup Complete With Errors" -ForegroundColor Red
    exit 1
}
