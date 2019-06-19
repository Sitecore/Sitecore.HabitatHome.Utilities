param(
    $instance = "habitathome.dev.local",
    #$identityServerUrl = "https://identityserver.habitathome.dev.local",
    [ValidateSet('xp', 'xc', 'sitecore')]
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

    Write-Host "Logging into Sitecore" -ForegroundColor Green
    $uri = "$site/sitecore/login?fbc=1"
    $authResponse = Invoke-WebRequest -uri $uri -SessionVariable session -UseBasicParsing
    TestStatusCode $authResponse

    # Set login info
    $fields = @{ }
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
# Function Get-SitecoreToken {
#     param(
#         [Parameter(Mandatory = $true, Position = 0)]
#         [string]$identityserverUrl,
#         [Parameter(Mandatory = $true, Position = 1)]
#         [string]$username,
#         [Parameter(Mandatory = $true, Position = 2)]
#         [string]$password
#     )
#     $tokenendpointurl = $identityserverUrl + "/connect/token"
#     $granttype = "password" # client_credentials / password 
#     $client_id = "warmup-client"
#     $client_secret = "ClientSecret"
#     $scope = "openid sitecore.profile sitecore.profile.api offline_access"
    
#     $body = @{
#         grant_type    = $granttype
#         scope         = $scope
#         client_id     = $client_id
#         client_secret = $client_secret    
#         username      = $username
#         password      = $password
#     }
#     $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
#     $headers.Add("Content-Type", 'application/x-www-form-urlencoded')
#     $headers.Add("Accept", 'application/json')

#     $resp = Invoke-RestMethod -Method Post -Body $body -Headers $headers -Uri $tokenendpointurl 

#     Write-Host "`***** SUCCESSFULLY FETCHED TOKEN ***** `n" -foreground Green

#     Write-Host "`ACCESS TOKEN: `n" -foreground Yellow
#     $access_token = $resp.access_token #| Format-Table -Wrap | Out-String
#     Write-Host $access_token -foreground White
#     Write-Host   
#     return $access_token
    
# }

Function RequestPage {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$url,
        [Parameter(Mandatory = $true, Position = 1)]
        [Microsoft.PowerShell.Commands.WebRequestSession]$session
    )
    Write-Host $(Get-Date -Format HH:mm:ss.fff)
    Write-Host "requesting $url ..."

    # $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    # $headers.Add("Authorization", ("Bearer {0}" -f $access_token))

    try { 
        
#        $response = Invoke-WebRequest -method Get $url -Headers $headers -TimeoutSec 60000 
        $response = Invoke-WebRequest $url -WebSession $session -TimeoutSec 60000 -UseBasicParsing

        if ($response.StatusCode -eq "200" ) {
            Write-Host "Success" 
            return $true
        }
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
#$session = Get-SitecoreToken $identityServerUrl ("sitecore\{0}" -f $adminUser) $adminPassword
$session = Get-SitecoreSession "https://$instanceName" ("sitecore\{0}" -f $adminUser) $adminPassword

$errors = 0

Write-Host "Warming up Sitecore" -ForegroundColor Green

foreach ($page in $config.urls.sitecore) {
    if (!$(RequestPage "https://$instanceName$($page.url)" $session)) {
        $errors++
    }
}

if ($demoType -eq ("xp" -or "xc")) {
    Write-Host "Warming up XP Demo" -ForegroundColor Green
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
