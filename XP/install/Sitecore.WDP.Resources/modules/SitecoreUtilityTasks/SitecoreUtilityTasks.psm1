Function Invoke-InstallModuleTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ModuleFullPath,
        [Parameter(Mandatory=$true)]
        [string]$ModulesDirDst,
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl
    )

    Copy-Item $ModuleFullPath -destination $ModulesDirDst -force

    $moduleToInstall = Split-Path -Path $ModuleFullPath -Leaf -Resolve


    Write-Host "Installing module: " $moduleToInstall -ForegroundColor Green ; 
    $urlInstallModules = $BaseUrl + "/InstallModules.aspx?modules=" + $moduleToInstall
    Write-Host $urlInstallModules
    Invoke-RestMethod $urlInstallModules -TimeoutSec 720
}

Function Invoke-InstallPackageTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageFullPath,
        [Parameter(Mandatory=$true)]
        [string]$PackagesDirDst,
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl
    )
	
	Copy-Item $PackageFullPath -destination $PackagesDirDst -force

    $packageToInstall = Split-Path -Path $PackageFullPath -Leaf -Resolve

    Write-Host "Installing package: " $packageToInstall -ForegroundColor Green ; 
    $urlInstallPackages = $BaseUrl + "/InstallPackages.aspx?package=" + $packageToInstall
    Write-Host $urlInstallPackages
    Invoke-RestMethod $urlInstallPackages -TimeoutSec 1800
}

Function Invoke-PublishToWebTask {
    [CmdletBinding()]
    param(        
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl
    )
	
    Write-Host "Publishing to web..." -ForegroundColor Green ; 
    Start-Sleep -Seconds 60
	$urlPublish = $BaseUrl + "/Publish.aspx"
	Invoke-RestMethod $urlPublish -TimeoutSec 1800
	Write-Host "Publishing to web complete..." -ForegroundColor Green ; 
}

Function Invoke-CreateDefaultStorefrontTask {
    [CmdletBinding()]
    param(        
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl,
		[Parameter(Mandatory=$false)]
        [string]$scriptName = "CreateDefaultStorefrontTenantAndSite",
		[Parameter(Mandatory=$false)]
        [string]$siteName = "",
		[Parameter(Mandatory=$true)]
        [string]$sitecoreUsername,
		[Parameter(Mandatory=$true)]
        [string]$sitecoreUserPassword
    )

	if($siteName -ne "")
	{
		Write-Host "Restarting the website and application pool for $($siteName)..." -ForegroundColor Green ; 
		Import-Module WebAdministration

		Stop-WebSite $siteName

		if((Get-WebAppPoolState $siteName).Value -ne 'Stopped')
 		{
 			Stop-WebAppPool -Name $siteName
 		}
	
 		Start-WebAppPool -Name $siteName
		Start-WebSite $siteName
		Write-Host "Restarting the website and application pool for $($siteName) complete..." -ForegroundColor Green ; 
	}

	Write-Host "Creating the default storefront..." -ForegroundColor Green ; 

	#Added Try catch to avoid deployment failure due to an issue in SPE 4.7.1 - Once fixed, we can remove this
	Try
	{
		$urlPowerShellScript = $BaseUrl + "/-/script/v2/master/$($scriptName)?user=$($sitecoreUsername)&password=$($sitecoreUserPassword)"
		Invoke-RestMethod $urlPowerShellScript -TimeoutSec 1200
	}
	Catch
	{
		$errorMessage = $_.Exception.Message
		Write-Host "Error occured: $errorMessage..." -ForegroundColor Red; 
	}
	
	Write-Host "Creating the default storefront complete..." -ForegroundColor Green; 
}

Function Invoke-RebuildIndexesTask {
    [CmdletBinding()]
    param(        
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl
    )
	
	Write-Host "Rebuilding index 'sitecore_core_index' ..." -ForegroundColor Green ; 
	$urlRebuildIndex = $BaseUrl + "/RebuildIndex.aspx?index=sitecore_core_index"
	Invoke-RestMethod $urlRebuildIndex -TimeoutSec 1200
	Write-Host "Rebuilding index 'sitecore_core_index' completed." -ForegroundColor Green ;    

	Write-Host "Rebuilding index 'sitecore_master_index' ..." -ForegroundColor Green ; 
	$urlRebuildIndex = $BaseUrl + "/RebuildIndex.aspx?index=sitecore_master_index"
	Invoke-RestMethod $urlRebuildIndex -TimeoutSec 1200
	Write-Host "Rebuilding index 'sitecore_master_index' completed." -ForegroundColor Green ; 	

	Write-Host "Rebuilding index 'sitecore_web_index' ..." -ForegroundColor Green ; 
	$urlRebuildIndex = $BaseUrl + "/RebuildIndex.aspx?index=sitecore_web_index"
	Invoke-RestMethod $urlRebuildIndex -TimeoutSec 1200
	Write-Host "Rebuilding index 'sitecore_web_index' completed." -ForegroundColor Green ; 
}

Function Invoke-GenerateCatalogTemplatesTask {
    [CmdletBinding()]
    param(        
        [Parameter(Mandatory=$true)]
        [string]$BaseUrl
    )  

	Write-Host "Generating Catalog Templates ..." -ForegroundColor Green ; 
	$urlGenerate = $BaseUrl + "/GenerateCatalogTemplates.aspx"
	Invoke-RestMethod $urlGenerate -TimeoutSec 180
	Write-Host "Generating Catalog Templates completed." -ForegroundColor Green ;
}

Function Invoke-DisableConfigFilesTask {
    [CmdletBinding()]
    param(        
        [Parameter(Mandatory=$true)]
        [string]$ConfigDir,
        [parameter(Mandatory=$true)]
        [string[]]$ConfigFileList
    )	

    foreach ($configFileName in $ConfigFileList) {
	    Write-Host "Disabling config file: $configFileName" -ForegroundColor Green;
	    $configFilePath = Join-Path $ConfigDir -ChildPath $configFileName
	    $disabledFilePath = "$configFilePath.disabled";

	    if (Test-Path $configFilePath) {
		    Rename-Item -Path $configFilePath -NewName $disabledFilePath;
		    Write-Host "  successfully disabled $configFilePath";
	    } else {
		    Write-Host "  configuration file not found." -ForegroundColor Red;
	    }
    }
}
Function Invoke-EnableConfigFilesTask {
    [CmdletBinding()]
    param(        
        [Parameter(Mandatory=$true)]
        [string]$ConfigDir,
        [parameter(Mandatory=$true)]
        [string[]]$ConfigFileList
    )	

    foreach ($configFileName in $ConfigFileList) {
	    Write-Host "Enabling config file: $configFileName" -ForegroundColor Green;
	    $configFilePath = Join-Path $ConfigDir -ChildPath $configFileName
	    $disabledFilePath = "$configFilePath.disabled";
	    $exampleFilePath = "$configFilePath.example";

	    if (Test-Path $configFilePath) {
		    Write-Host "  config file is already enabled...";
	    } elseif (Test-Path $disabledFilePath) {
		    Rename-Item -Path $disabledFilePath -NewName $configFileName;
		    Write-Host "  successfully enabled $disabledFilePath";
	    } elseif (Test-Path $exampleFilePath) {
		    Rename-Item -Path $exampleFilePath -NewName $configFileName;
		    Write-Host "  successfully enabled $exampleFilePath";
	    } else {
		    Write-Host "  configuration file not found." -ForegroundColor Red;
	    }
    }
}

Function Invoke-ExpandArchive {
    [CmdletBinding()]
    param(        
        [Parameter(Mandatory=$true)]
        [string]$SourceZip,
        [parameter(Mandatory=$true)]
        [string]$DestinationPath
    )	

    Expand-Archive $SourceZip -DestinationPath $DestinationPath -Force
}

Register-SitecoreInstallExtension -Command Invoke-InstallModuleTask -As InstallModule -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-InstallPackageTask -As InstallPackage -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-PublishToWebTask -As PublishToWeb -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-RebuildIndexesTask -As RebuildIndexes -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-GenerateCatalogTemplatesTask -As GenerateCatalogTemplates -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-EnableConfigFilesTask -As EnableConfigFiles -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-DisableConfigFilesTask -As DisableConfigFiles -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-CreateDefaultStorefrontTask -As CreateDefaultStorefront -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-ExpandArchive -As ExpandArchive -Type Task -Force