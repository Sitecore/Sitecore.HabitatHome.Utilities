Param(
    [string] $hostName = "my.hostname",
    [string]$CertificateName = "my.hostname",
    [string[]]$sites = @("habitathome.dev.local:443")
)


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