param
(
    [Parameter(Mandatory = $false)][string] $deploy = "OnPrem",
    [Parameter(Mandatory = $false)][string] $topology = "xp0",
    [Parameter(Mandatory = $false)][string] $instanceName = $topology,
    [Parameter(Mandatory = $false)][string] $instanceVersion = (Get-Content "./program.version"),
    [Parameter(Mandatory = $false)][string] $instanceRevision,
    [Parameter(Mandatory = $false)][string] $sqlServer = ".",
    [Parameter(Mandatory = $false)][string] $dbUser = "sa",
    [Parameter(Mandatory = $false)][string] $dbPassword = "Sitecore12!@",
    [Parameter(Mandatory = $false)][string] $instanceUser = "admin",
    [Parameter(Mandatory = $false)][string] $instancePassword = "b",
    [Parameter(Mandatory = $false)][string] $wdpResourcesFeed = "http://nuget1dk1/nuget/${instanceVersion}_IPA/",
    [Parameter(Mandatory = $false)][string] $toolsFeed = "http://nuget1dk1/nuget/Tools/",
    [Parameter(Mandatory = $false)][string] $jsonFile,
    [Parameter(Mandatory = $false)][string] $SolrPort = "8721",
    [Parameter(Mandatory = $false)][string] $websiteDir = "C:\inetpub\wwwroot"
)
if (-not $skipDeploy -and [string]::IsNullOrEmpty($jsonFile)) {
    $filter = "Sitecore $instanceVersion rev. "
    if ($instanceRevision) {
        $filter += $instanceRevision
    }
    $paths = Get-ChildItem `
        -Path "\\mars\QA\$($instanceVersion.Substring(0,3))\$instanceVersion\" `
        -Recurse -Depth 2 -Include "wdpUrls_OnPrem.json" `
        | Sort-Object {$_.Directory.CreationTime} | Where-Object {$_.FullName -like "*$filter*"}
    $jsonFile = $paths[-1].FullName
}
$buildNumber = (Split-Path (Split-Path $jsonFile -Parent) -Leaf) -replace "Sitecore ", ""
Write-Host "##teamcity[buildNumber '$buildNumber']"
Write-Host ">>> JSON file: $jsonFile" -foregroundcolor Blue