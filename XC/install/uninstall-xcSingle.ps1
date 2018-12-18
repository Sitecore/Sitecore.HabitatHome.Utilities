Param(
    [string] $ConfigurationFile = '.\configuration-xc0.json',
    [string[]] $Environments = @("CommerceOps", "CommerceShops", "CommerceAuthoring", "CommerceMinions")
)

#####################################################
#
#  Install Sitecore
#
#####################################################
$ErrorActionPreference = 'Stop'
#Set-Location $PSScriptRoot

if (!(Test-Path $ConfigurationFile)) {
    Write-Host 'Configuration file '$($ConfigurationFile)' not found.' -ForegroundColor Red
    Write-Host  'Please use 'set-installation...ps1' files to generate a configuration file.' -ForegroundColor Red
    Exit 1
}

$config = Get-Content -Raw $ConfigurationFile -Encoding Ascii |  ConvertFrom-Json

if (!$config) {
    throw "Error trying to load configuration!"
}

$site = $config.settings.site
$sql = $config.settings.sql
$solr = $config.settings.solr
$commerce = $config.settings.commerce
Function Write-TaskHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskName,
        [Parameter(Mandatory = $true)]
        [string]$TaskType
    )

    function StringFormat {
        param(
            [int]$length,
            [string]$value,
            [string]$prefix = '',
            [string]$postfix = '',
            [switch]$padright
        )

        # wraps string in spaces so we reduce length by two
        $length = $length - 2 #- $postfix.Length - $prefix.Length
        if ($value.Length -gt $length) {
            # Reduce to length - 4 for elipsis
            $value = $value.Substring(0, $length - 4) + '...'
        }

        $value = " $value "
        if ($padright) {
            $value = $value.PadRight($length, '*')
        }
        else {
            $value = $value.PadLeft($length, '*')
        }

        return $prefix + $value + $postfix
    }

    $actualWidth = (Get-Host).UI.RawUI.BufferSize.Width
    $width = $actualWidth - ($actualWidth % 2)
    $half = $width / 2

    $leftString = StringFormat -length $half -value $TaskName -prefix '[' -postfix ':'
    $rightString = StringFormat -length $half -value $TaskType -postfix ']' -padright

    $message = ($leftString + $rightString)
    Write-Host ''
    Write-Host $message -ForegroundColor 'Red'
}

Function Remove-Website {
    [CmdletBinding()]
    param(
        [string]$siteName		
    )

    $appCmd = "C:\windows\system32\inetsrv\appcmd.exe"
    & $appCmd delete site $siteName
}

Function Remove-AppPool {
    [CmdletBinding()]
    param(		
        [string]$appPoolName
    )

    $appCmd = "C:\windows\system32\inetsrv\appcmd.exe"
    & $appCmd delete apppool $appPoolName
}

#Stop Solr Service
Write-TaskHeader -TaskName "Solr Services" -TaskType "Stop"
Write-Host "Stopping solr service"
Stop-Service $solr.serviceName -Force -ErrorAction SilentlyContinue
Write-Host "Solr service stopped successfully"

#Delete solr cores
Write-TaskHeader -TaskName "Solr Services" -TaskType "Delete Cores"
Write-Host "Deleting Solr Cores"
$pathToCores = "$($solr.root)\server\solr"
$cores = @("CatalogItemsScope", "CustomersScope", "OrdersScope")

foreach ($core in $cores) {
    Remove-Item (Join-Path $pathToCores "$($site.prefix)$core") -recurse -force -ErrorAction SilentlyContinue
}
Write-Host "Solr Cores deleted successfully"
Write-TaskHeader -TaskName "Solr Services" -TaskType "Start"
Write-Host "Starting solr service"
Start-Service $solr.serviceName  -ErrorAction SilentlyContinue
Write-Host "Solr service started successfully"
#Remove Sites and App Pools from IIS
Write-TaskHeader -TaskName "Internet Information Services" -TaskType "Remove Websites"

foreach ($environment in $Environments) {
    $siteName = ("{0}_{1}" -f $environment, $site.prefix)
    Write-Host ("Deleting Website  {0}" -f $siteName)
    Remove-Website -siteName $siteName -ErrorAction SilentlyContinue
    Remove-AppPool -appPoolName $siteName
    Remove-Item ("$($site.webRoot)\{0}" -f $siteName) -recurse -force -ErrorAction SilentlyContinue
    Remove-Item ("$($site.webRoot)\{0}_backup" -f $siteName) -recurse -force -ErrorAction SilentlyContinue
}
$bizfxPrefix = "SitecoreBizFx"
$bizfx = ("{0}_{1}" -f $bizfxPrefix, $site.prefix)
Write-Host ("Deleting Website {0}" -f $bizfx)
Remove-Website -siteName $bizfx -ErrorAction SilentlyContinue
Remove-AppPool -appPoolName $bizfx
Remove-Item ("$($site.webRoot)\{0}" -f $bizfx) -recurse -force -ErrorAction SilentlyContinue

Write-Host ("Deleting Website {0}" -f $commerce.identityServerName)
Remove-Website -siteName $commerce.identityServerName -ErrorAction SilentlyContinue
Remove-AppPool -appPoolName $commerce.identityServerName
Remove-Item ("$($site.webRoot)\{0}" -f $commerce.identityServerName) -recurse -force -ErrorAction SilentlyContinue

Write-TaskHeader -TaskName "SQL Server" -TaskType "Drop Databases"
#Drop databases from SQL
Write-Host "Dropping databases from SQL server"
push-location
import-module sqlps
$databases = @("Global", "SharedEnvironments")
foreach ($db in $databases) {
    $dbName = ("{0}_{1}" -f $site.prefix, $db)
    Write-Host $("Dropping database {0}" -f $dbName)
    $sqlCommand = $("DROP DATABASE IF EXISTS {0}" -f $dbName)
    Write-Host $("Query: $($sqlCommand)")
    invoke-sqlcmd -ServerInstance $sql.server -Username $sql.adminUser -Password $sql.adminPassword -Query $sqlCommand -ErrorAction SilentlyContinue
}

Write-Host "Databases dropped successfully"
pop-location
Write-TaskHeader -TaskName "Uninstallation Complete" -TaskType "Uninstall Complete"