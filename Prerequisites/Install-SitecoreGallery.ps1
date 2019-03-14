param (
    [string]$nugetServer="http://nuget1ca2/nuget/Sitecore_Gallery"
)

$gallery = Get-PSRepository|Where-Object {$_.Name -eq "SitecoreGallery"} 

if (!$gallery) {
    Register-PSRepository -Name SitecoreGallery -SourceLocation $nugetServer -PublishLocation $nugetServer -InstallationPolicy Trusted
}
elseif (($gallery.SourceLocation -ne $nugetServer) -or ($gallery.PublishLocation -ne $nugetServer) -or !$gallery.Trusted) {
    Set-PSRepository -Name SitecoreGallery -SourceLocation $nugetServer -PublishLocation $nugetServer -InstallationPolicy Trusted
}

Get-PSRepository -Name "SitecoreGallery" | Format-List * -Force
