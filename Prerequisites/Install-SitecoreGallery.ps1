param (
    [string]$nugetServer="https://sitecore.myget.org/F/sc-powershell/api/v2/"
)

$repositoryName = "SitecoreGallery"
$gallery = Get-PSRepository | Where-Object { $_.Name -eq $repositoryName }

if (!$gallery) {
    Register-PSRepository -Name $repositoryName -SourceLocation $nugetServer -PublishLocation $nugetServer -InstallationPolicy Trusted
}
elseif (($gallery.SourceLocation -ne $nugetServer) -or ($gallery.PublishLocation -ne $nugetServer) -or !$gallery.Trusted) {
    Set-PSRepository -Name $repositoryName -SourceLocation $nugetServer -PublishLocation $nugetServer -InstallationPolicy Trusted
}

Get-PSRepository -Name $repositoryName | Format-List * -Force
