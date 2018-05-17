Param(
    $nuGetServer = "http://nuget1ca2",
    $packageList = "C:\projects\test.json",
    $overwrite = $true,
    $destinationDirectory = "C:\LocalGetTest" 
)
# --- locals ---
$webClient = New-Object System.Net.WebClient
Function DownloadEntry {
    param (
        $packageUrl,
    $packageName,
    $packageVersion
    ) 
        Write-Host ("Processing {0}" -f $packageUrl)
        Write-Host ("Package Name: {0} - Package Version {1}"-f $packageName,$packageVersion)
        [string]$url = $packageUrl
        $fileName = $packageName + "." + $packageVersion + ".nupkg"
        $saveFileName = join-path $destinationDirectory $fileName
        Write-Host ("Saving to {0}"-f $saveFileName)
        if ((-not $overwrite) -and (Test-Path -path $saveFileName)) {
            write-progress -activity "$fileName already downloaded" `
            continue
        }
        write-progress -activity "Downloading $fileName" 

        [int]$trials = 0
        do {
            try {
                $trials += 1
                $webClient.DownloadFile($url, $saveFileName)
                break
            }
            catch [System.Net.WebException] {
                write-host "Problem downloading $url `tTrial $trials `
                       `n`tException: " $_.Exception.Message
            }
        }
        while ($trials -lt 3)
    
    }

# if dest dir doesn't exist, create it
if (!(Test-Path -path $destinationDirectory)) { 
    New-Item $destinationDirectory -type directory 
}
# Load package JSON
$packages = Get-Content $packageList | ConvertFrom-Json

# set up feed URL
$serviceBase = $feedUrlBase

Write-Host $feedUrl
foreach ($package in $packages.packages ) {
    $feedUrl = $nuGetServer
    $packagePath = ("/nuget/Commerce/package/{0}/{1}" -f $package.Name,$package.Version)
    $feedUrl = $feedUrl + $packagePath
        DownloadEntry $feedUrl $package.Name $package.Version
    
}


