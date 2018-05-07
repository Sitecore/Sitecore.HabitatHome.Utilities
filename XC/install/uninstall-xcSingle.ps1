#define parameters
Param(
	[string]$Prefix = 'sc901com',	
	[string]$CommerceOpsSiteName = 'CommerceOps_Sc9',
	[string]$CommerceShopsSiteName = 'CommerceShops_Sc9',
	[string]$CommerceAuthoringSiteName = 'CommerceAuthoring_Sc9',
	[string]$CommerceMinionsSiteName = 'CommerceMinions_Sc9',
	[string]$SitecoreBizFxSiteName = 'SitecoreBizFx',
	[string]$SitecoreIdentityServerSiteName = 'SitecoreIdentityServer',
	[string]$SolrService = 'Solr_6.6.2',
	[string]$PathToSolr = 'E:\sc9_install\solr-6.6.2\',
	[string]$SqlServer = 'DESKTOP-XXXXXX\MSSQLSERVER2017',
	[string]$SqlAccount = 'sa',
	[string]$SqlPassword = 'password'
)
#Write-TaskHeader function modified from SIF
Function Write-TaskHeader {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TaskName,
        [Parameter(Mandatory=$true)]
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
        if($value.Length -gt $length){
            # Reduce to length - 4 for elipsis
            $value = $value.Substring(0, $length - 4) + '...'
        }

        $value = " $value "
        if($padright){
            $value = $value.PadRight($length, '*')
        } else {
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

Function Remove-Service{
	[CmdletBinding()]
	param(
		[string]$serviceName
	)
	if(Get-Service "My Service" -ErrorAction SilentlyContinue){
		sc.exe delete $serviceName
	}
}

Function Remove-Website{
	[CmdletBinding()]
	param(
		[string]$siteName		
	)

	$appCmd = "C:\windows\system32\inetsrv\appcmd.exe"
	& $appCmd delete site $siteName
}

Function Remove-AppPool{
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
Stop-Service $SolrService -Force -ErrorAction stop
Write-Host "Solr service stopped successfully"

#Delete solr cores
Write-TaskHeader -TaskName "Solr Services" -TaskType "Delete Cores"
Write-Host "Deleting Solr Cores"
$pathToCores = "$pathToSolr\server\solr\$Prefix*"
Remove-Item $pathToCores -recurse -force -ErrorAction stop
Write-Host "Solr Cores deleted successfully"

#Remove Sites and App Pools from IIS
Write-TaskHeader -TaskName "Internet Information Services" -TaskType "Remove Websites"


Write-Host "Deleting Website $CommerceOpsSiteName"
Remove-Website -siteName $CommerceOpsSiteName -ErrorAction stop
Write-Host "Websites deleted"

Write-Host "Deleting Website $CommerceShopsSiteName"
Remove-Website -siteName $CommerceShopsSiteName -ErrorAction stop
Write-Host "Websites deleted"

Write-Host "Deleting Website $CommerceAuthoringSiteName"
Remove-Website -siteName $CommerceAuthoringSiteName -ErrorAction stop
Write-Host "Websites deleted"

Write-Host "Deleting Website $CommerceMinionsSiteName "
Remove-Website -siteName $CommerceMinionsSiteName  -ErrorAction stop
Write-Host "Websites deleted"

Write-Host "Deleting Website $SitecoreBizFxSiteName"
Remove-Website -siteName $SitecoreBizFxSiteName -ErrorAction stop
Write-Host "Websites deleted"

Write-Host "Deleting Website $SitecoreIdentityServerSiteName"
Remove-Website -siteName $SitecoreIdentityServerSiteName -ErrorAction stop
Write-Host "Websites deleted"



Remove-AppPool -appPoolName $CommerceOpsSiteName -ErrorAction stop
Write-Host "Application pools deleted"
Remove-AppPool -appPoolName $CommerceShopsSiteName -ErrorAction stop
Write-Host "Application pools deleted"
Remove-AppPool -appPoolName $CommerceAuthoringSiteName -ErrorAction stop
Write-Host "Application pools deleted"
Remove-AppPool -appPoolName $CommerceMinionsSiteName -ErrorAction stop
Write-Host "Application pools deleted"
Remove-AppPool -appPoolName $SitecoreBizFxSiteName -ErrorAction stop
Write-Host "Application pools deleted"
Remove-AppPool -appPoolName $SitecoreIdentityServerSiteName -ErrorAction stop


Remove-Item C:\inetpub\wwwroot\$CommerceOpsSiteName -recurse -force -ErrorAction stop
Write-Host "Websites removed from wwwroot"
Remove-Item C:\inetpub\wwwroot\$CommerceShopsSiteName -recurse -force -ErrorAction stop
Write-Host "Websites removed from wwwroot"
Remove-Item C:\inetpub\wwwroot\$CommerceAuthoringSiteName -recurse -force -ErrorAction stop
Write-Host "Websites removed from wwwroot"
Remove-Item C:\inetpub\wwwroot\$CommerceMinionsSiteName -recurse -force -ErrorAction stop
Write-Host "Websites removed from wwwroot"
Remove-Item C:\inetpub\wwwroot\$SitecoreBizFxSiteName -recurse -force -ErrorAction stop
Write-Host "Websites removed from wwwroot"
Remove-Item C:\inetpub\wwwroot\$SitecoreIdentityServerSiteName -recurse -force -ErrorAction stop
Write-Host "Websites removed from wwwroot"


Write-TaskHeader -TaskName "SQL Server" -TaskType "Drop Databases"
#Drop databases from SQL
Write-Host "Dropping databases from SQL server"
push-location
import-module sqlps

Write-Host $("Dropping database SitecoreCommerce9_Global")
$commerceDbPrefix = $("DROP DATABASE IF EXISTS [SitecoreCommerce9_Global]")
Write-Host $("Query: $($commerceDbPrefix)")
invoke-sqlcmd -ServerInstance $SqlServer -U $SqlAccount -P $SqlPassword -Query $commerceDbPrefix -ErrorAction stop

Write-Host $("Dropping database [SitecoreCommerce9_SharedEnvironments]")
$sharedDbPrefix = $("DROP DATABASE IF EXISTS [SitecoreCommerce9_SharedEnvironments]")
Write-Host $("Query: $($sharedDbPrefix)")
invoke-sqlcmd -ServerInstance $SqlServer -U $SqlAccount -P $SqlPassword -Query $sharedDbPrefix -ErrorAction stop


Write-Host "Databases dropped successfully"
pop-location
