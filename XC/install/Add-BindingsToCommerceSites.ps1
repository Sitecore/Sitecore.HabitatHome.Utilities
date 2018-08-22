Param(
    [string] $hostName = "my.hostname",
    [string]$CertificateName = "my.hostname",
    [string[]]$sites = @("CommerceAuthoring_habitathome:5000", "CommerceMinions_habitathome:5010", "CommerceOps_habitathome:5015", "CommerceShops_habitathome:5020", "SitecoreBizFx:4200", "SitecoreIdentityServer:5050")
)

Set-Location (Resolve-Path "..\..\XP\Install")

foreach ($site in $sites) {
    $siteName = $site.split(":")[0]
    $port = $site.split(":")[1]

    #   Remove -SkipCreateCert if you would like to create a new certificate

    if ($siteName -ne "habitathome.dev.local") {

        .\Add-SSLSiteBindingWithCertificate.ps1 -SiteName $siteName -Port $port -HostName $hostName -CertificateName $CertificateName -SkipCreateCert -SslOnly
    }
    else {
        .\Add-SSLSiteBindingWithCertificate.ps1 -SiteName $siteName -Port $port -HostName $hostName -CertificateName $CertificateName -SkipCreateCert

    }
}