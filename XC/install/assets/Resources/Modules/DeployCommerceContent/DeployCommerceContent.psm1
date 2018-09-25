
Function Invoke-DeployCommerceContentTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [string]$ServicesContentPath,
        [Parameter(Mandatory=$true)]
        [string]$PhysicalPath,
        [Parameter(Mandatory=$true)]
        [psobject[]]$UserAccount = @(),
        [Parameter(Mandatory=$false)]
        [psobject[]]$BraintreeAccount = @(),
        [Parameter(Mandatory=$false)]
        [string]$CommerceSearchProvider,
        [Parameter(Mandatory=$false)]
        [string]$SitecoreDbServer,
        [Parameter(Mandatory=$false)]
        [string]$SitecoreCoreDbName,
		[Parameter(Mandatory=$false)]
        [string]$CommerceServicesDbServer,
		[Parameter(Mandatory=$false)]
        [string]$CommerceServicesDbName,
		[Parameter(Mandatory=$false)]
        [string]$CommerceServicesGlobalDbName,
        [Parameter(Mandatory=$false)]
        [string]$SiteHostHeaderName,
        [Parameter(Mandatory=$false)]
        [string]$CommerceAuthoringServicesPort,
		[Parameter(Mandatory=$false)]
        [string]$SolrUrl,
		[Parameter(Mandatory=$false)]
        [string]$SearchIndexPrefix,		
		[Parameter(Mandatory=$false)]
        [string]$AzureSearchServiceName,		
		[Parameter(Mandatory=$false)]
        [string]$AzureSearchAdminKey,		
		[Parameter(Mandatory=$false)]
        [string]$AzureSearchQueryKey	,
        [Parameter(Mandatory = $false)]
        [string]$EnvironmentName		
    )

    try {       
        switch ($Name) {
            {($_ -match "CommerceOps")} {                    
				Write-Host
				$global:opsServicePath = $PhysicalPath	
				$commerceServicesItem =  Get-Item $ServicesContentPath | select-object -first 1
		if (Test-Path $commerceServicesItem -PathType Leaf) {
                    # Assume path to zip file passed in, extract zip to $PhysicalPath
                    #Extracting the CommerceServices zip file Commerce Shops Services
                    Write-Host "Extracting CommerceServices from $commerceServicesItem to $PhysicalPath" -ForegroundColor Yellow ;
                    Expand-Archive $commerceServicesItem -DestinationPath $PhysicalPath -Force
                }
                else {
                    # Assume path is to a published Commerce Engine folder. Copy the contents of the folder to the $PhysicalPath
                    Write-Host "Copying the contents of CommerceServices from $commerceServicesItem to $PhysicalPath" -ForegroundColor Yellow ;
                    Copy-Item -Path $commerceServicesItem -Destination $PhysicalPath -Force -Recurse
                }
                Write-Host "Commerce OpsApi Services copy/extraction completed" -ForegroundColor Green ;


				$commerceServicesLogDir = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\logs")                
                if(-not (Test-Path -Path $commerceServicesLogDir)) {                      
				    Write-Host "Creating Commerce Services logs directory at: $commerceServicesLogDir"
				    New-Item -Path $PhysicalPath -Name "wwwroot\logs" -ItemType "directory"
                }

				Write-Host "Granting full access to '$($UserAccount.Domain)\$($UserAccount.UserName)' to logs directory: $commerceServicesLogDir"
				GrantFullReadWriteAccessToFile -Path $commerceServicesLogDir  -UserName "$($UserAccount.Domain)\$($UserAccount.UserName)"							

				# Set the proper environment name                
				$pathToJson  = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\config.json")
				$originalJson = Get-Content $pathToJson -Raw  | ConvertFrom-Json
				
				if ($EnvironmentName -ne "") {
                    #$originalJson.AppSettings.EnvironmentName = $EnvironmentName
                    $originalJson.AppSettings.EnvironmentName = "AdventureWorksOpsApi"
                }
                else {
                    $originalJson.AppSettings.EnvironmentName = "AdventureWorksOpsApi"    
                }
				
                #TODO: Should take a list of allowed origins in parameters
                $allowedOrigins = @("https://localhost:4200", "https://$SiteHostHeaderName","https://habitat.dev.local","https://habitathome.dev.local")
                $originalJson.AppSettings.AllowedOrigins = $allowedOrigins 
                
                $originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $pathToJson

                #Replace database name in Global.json
                $pathToGlobalJson  = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\bootstrap\Global.json")
				$originalJson = Get-Content $pathToGlobalJson -Raw  | ConvertFrom-Json
				foreach ($p in $originalJson.Policies.'$values') {
					if ($p.'$type' -eq 'Sitecore.Commerce.Plugin.SQL.EntityStoreSqlPolicy, Sitecore.Commerce.Plugin.SQL') {						
						$oldServer = $p.Server
						$oldDatabase = $p.Database
						$p.Server = $CommerceServicesDbServer
						$p.Database = $CommerceServicesGlobalDbName
                        Write-Host "Replacing in EntityStoreSqlPolicy $oldServer to $p.Server and $oldDatabase to $p.Database"
					} elseif ($p.'$type' -eq 'Sitecore.Commerce.Plugin.Management.SitecoreConnectionPolicy, Sitecore.Commerce.Plugin.Management') {
						if ($SiteHostHeaderName -ne "sxa.storefront.com") {
							$p.Host = $SiteHostHeaderName	
							Write-Host "Replacing in SitecoreConnectionPolicy 'sxa.storefront.com' with $SiteHostHeaderName"
						}
					} elseif ($p.'$type' -eq 'Plugin.Sample.Upgrade.MigrationSqlPolicy, Plugin.Sample.Upgrade') {
						$oldServer = $p.SourceStoreSqlPolicy.Server
						$oldDatabase = $p.SourceStoreSqlPolicy.Database
						$p.SourceStoreSqlPolicy.Server = $CommerceServicesDbServer
						$p.SourceStoreSqlPolicy.Database = $CommerceServicesGlobalDbName
						Write-Host "Replacing in MigrationSqlPolicy $oldServer to $p.SourceStoreSqlPolicy.Server and $oldDatabase to $p.SourceStoreSqlPolicy.Database"
					}
				}
				$originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $pathToGlobalJson
				
                $pathToEnvironmentFiles = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\data\Environments")

				# if setting up Azure search provider we need to rename the azure and solr files
				if ($CommerceSearchProvider -eq 'AZURE') {

					#rename the azure file from .disabled and disable the Solr policy file
					$AzurePolicyFile = Get-ChildItem "$pathToEnvironmentFiles\PlugIn.Search.Azure.PolicySet*.disabled"
					$SolrPolicyFile = Get-ChildItem "$pathToEnvironmentFiles\PlugIn.Search.Solr.PolicySet*.json"
					$newName = ($AzurePolicyFile.FullName -replace ".disabled",'');
					RenameMessage $($AzurePolicyFile.FullName) $($newName);
					Rename-Item $AzurePolicyFile -NewName $newName -f;
					$newName = ($SolrPolicyFile.FullName -replace ".json",'.json.disabled');
					RenameMessage $($SolrPolicyFile.FullName) $($newName);
					Rename-Item $SolrPolicyFile -NewName $newName -f;
					Write-Host "Renaming search provider policy sets to enable Azure search"
				}

				#Replace database name in environment files
				$Writejson = $false
				$environmentFiles = Get-ChildItem $pathToEnvironmentFiles -Filter *.json
				foreach ($jsonFile in $environmentFiles) {
					$json = Get-Content $jsonFile.FullName -Raw | ConvertFrom-Json
					foreach ($p in $json.Policies.'$values') {
						if ($p.'$type' -eq 'Sitecore.Commerce.Plugin.SQL.EntityStoreSqlPolicy, Sitecore.Commerce.Plugin.SQL') {
							$oldServer = $p.Server
							$oldDatabase = $p.Database;
							$Writejson = $true
							$p.Server = $CommerceServicesDbServer
							$p.Database =  $CommerceServicesDbName
							Write-Host "Replacing in EntityStoreSqlPolicy $oldServer with $CommerceServicesDbServer and $oldDatabase with $CommerceServicesDbName"
                        } elseif ($p.'$type' -eq 'Sitecore.Commerce.Plugin.Management.SitecoreConnectionPolicy, Sitecore.Commerce.Plugin.Management') {
							if ($SiteHostHeaderName -ne "sxa.storefront.com") {
								$oldHost = $p.Host;
								$Writejson = $true
								$p.Host =  $SiteHostHeaderName
								Write-Host "Replacing SiteHostHeaderName $oldHost with $SiteHostHeaderName"
							}
						} elseif ($p.'$type' -eq 'Sitecore.Commerce.Plugin.Search.Solr.SolrSearchPolicy, Sitecore.Commerce.Plugin.Search.Solr') {
							$p.SolrUrl = $SolrUrl;
							$Writejson = $true;
							Write-Host "Replacing Solr Url"
						} elseif ($p.'$type' -eq 'Sitecore.Commerce.Plugin.Search.Azure.AzureSearchPolicy, Sitecore.Commerce.Plugin.Search.Azure') {
							$p.SearchServiceName = $AzureSearchServiceName;
							$p.SearchServiceAdminApiKey = $AzureSearchAdminKey;
							$p.SearchServiceQueryApiKey = $AzureSearchQueryKey;
							$Writejson = $true;
							Write-Host "Replacing Azure service information"
						} elseif ($p.'$type' -eq 'Plugin.Sample.Payments.Braintree.BraintreeClientPolicy, Plugin.Sample.Payments.Braintree') {
							$p.MerchantId = $BraintreeAccount.MerchantId;
							$p.PublicKey = $BraintreeAccount.PublicKey;
							$p.PrivateKey = $BraintreeAccount.PrivateKey;
							$Writejson = $true;
							Write-Host "Inserting Braintree account"
						} elseif ($p.'$type' -eq 'Sitecore.Commerce.Core.PolicySetPolicy, Sitecore.Commerce.Core' -And $p.'PolicySetId' -eq 'Entity-PolicySet-SolrSearchPolicySet') {
							if ($CommerceSearchProvider -eq 'AZURE') {
								$p.'PolicySetId' = 'Entity-PolicySet-AzureSearchPolicySet';
								$Writejson = $true
							}
						}
					}
					if ($Writejson) {
						$json = ConvertTo-Json $json -Depth 100
						Set-Content $jsonFile.FullName -Value $json -Encoding UTF8
						$Writejson = $false
					}
				}
								
				if ([string]::IsNullOrEmpty($SearchIndexPrefix) -eq $false) {
					#modify the search policy set
					$jsonFile = Get-ChildItem "$pathToEnvironmentFiles\PlugIn.Search.PolicySet*.json"
					$json = Get-Content $jsonFile.FullName -Raw | ConvertFrom-Json
					$indexes = @()
					# Generically update the different search scope policies so it will be updated for any index that exists or is created in the future
					Foreach ($p in $json.Policies.'$values') {
						if ($p.'$type' -eq 'Sitecore.Commerce.Plugin.Search.SearchViewPolicy, Sitecore.Commerce.Plugin.Search') {
							$oldSearchScopeName = $p.SearchScopeName
							$searchScopeName = "$SearchIndexPrefix$oldSearchScopeName"
							$p.SearchScopeName = $searchScopeName;
							$Writejson = $true;

							Write-Host "Replacing SearchViewPolicy SearchScopeName $oldSearchScopeName with $searchScopeName"

							# Use this to figure out what indexes will exist
							$indexes += $searchScopeName
						}

						if ($p.'$type' -eq 'Sitecore.Commerce.Plugin.Search.SearchScopePolicy, Sitecore.Commerce.Plugin.Search') 
						{
							$oldName = $p.Name
							$name = "$SearchIndexPrefix$oldName"
							$p.Name = $name;
							$Writejson = $true;

							Write-Host "Replacing SearchScopePolicy Name $oldName with $name"
						}

						if ($p.'$type' -eq 'Sitecore.Commerce.Plugin.Search.IndexablePolicy, Sitecore.Commerce.Plugin.Search') 
						{
							$oldSearchScopeName = $p.SearchScopeName
							$searchScopeName = "$SearchIndexPrefix$oldSearchScopeName"
							$p.SearchScopeName = $searchScopeName;
							$Writejson = $true;

							Write-Host "Replacing IndexablePolicy SearchScopeName $oldSearchScopeName with $searchScopeName"
						}
					}
					
					if ($Writejson) {
						$json = ConvertTo-Json $json -Depth 100
						Set-Content $jsonFile.FullName -Value $json -Encoding UTF8
						$Writejson = $false
					}
				}
            }
            {($_ -match "CommerceShops") -or ($_ -match "CommerceAuthoring") -or ($_ -match "CommerceMinions")}  {
                # Copy the the CommerceServices files to the $Name Services
				Write-Host "Copying Commerce Services from $global:opsServicePath to $PhysicalPath" -ForegroundColor Yellow ;
				Copy-Item -Path $global:opsServicePath -Destination $PhysicalPath -Force -Recurse
				Write-Host "Commerce Shops Services extraction completed" -ForegroundColor Green ;

				$commerceServicesLogDir = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\logs")
				if(-not (Test-Path -Path $commerceServicesLogDir)) {                      
				    Write-Host "Creating Commerce Services logs directory at: $commerceServicesLogDir"
				    New-Item -Path $PhysicalPath -Name "wwwroot\logs" -ItemType "directory"
                }
				
				Write-Host "Granting full access to '$($UserAccount.Domain)\$($UserAccount.UserName)' to logs directory: $commerceServicesLogDir"
				GrantFullReadWriteAccessToFile -Path $commerceServicesLogDir  -UserName "$($UserAccount.Domain)\$($UserAccount.UserName)"

				# Set the proper environment name
				$pathToJson  = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\config.json")
				$originalJson = Get-Content $pathToJson -Raw | ConvertFrom-Json
				 if ($EnvironmentName -ne "") {
                    $environment = $EnvironmentName
                }
                else {
				$environment = "HabitatShops"
				if ($Name -match "CommerceAuthoring"){
					$environment = "HabitatAuthoring"
				}elseif ($Name -match "CommerceMinions"){
					$environment = "HabitatMinions"
				}
				}
				$originalJson.AppSettings.EnvironmentName = $environment
				$originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $pathToJson
			}               
            'SitecoreIdentityServer' {
				Write-Host
				# Extracting Sitecore.IdentityServer zip file
				$commerceServicesItem =  Get-Item $ServicesContentPath | select-object -first 1
			
			if (Test-Path $commerceServicesItem -PathType Leaf) {
                    # Assume path to zip file passed in, extract zip to $PhysicalPath
                    #Extracting the CommerceServices zip file Commerce Shops Services
                    Write-Host "Extracting Sitecore.IdentityServer from $commerceServicesZip to $PhysicalPath" -ForegroundColor Yellow ;
                    Expand-Archive $commerceServicesItem -DestinationPath $PhysicalPath -Force
                }
                else {
                    # Assume path is to a published Commerce Engine folder. Copy the contents of the folder to the $PhysicalPath
                    Write-Host "Copying the contents of CommerceServices from $commerceServicesItem to $PhysicalPath" -ForegroundColor Yellow ;
                    Copy-Item -Path $commerceServicesItem -Destination $PhysicalPath -Force -Recurse
                }

				Write-Host "Sitecore.IdentityServer extraction completed" -ForegroundColor Green ;

				$commerceServicesLogDir = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\logs")
				if(-not (Test-Path -Path $commerceServicesLogDir)) {                      
				    Write-Host "Creating Commerce Services logs directory at: $commerceServicesLogDir"
				    New-Item -Path $PhysicalPath -Name "wwwroot\logs" -ItemType "directory"
                }
				
				Write-Host "Granting full access to '$($UserAccount.Domain)\$($UserAccount.UserName)' to logs directory: $commerceServicesLogDir"
				GrantFullReadWriteAccessToFile -Path $commerceServicesLogDir  -UserName "$($UserAccount.Domain)\$($UserAccount.UserName)"
				
				$appSettingsPath = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\appsettings.json")
				$originalJson = Get-Content $appSettingsPath -Raw | ConvertFrom-Json
				$connectionString = $originalJson.AppSettings.SitecoreMembershipOptions.ConnectionString
				$connectionString = $connectionString -replace "SXAStorefrontSitecore_Core", $SitecoreCoreDbName
				$connectionString = $connectionString -replace "localhost", $SitecoreDbServer
				$originalJson.AppSettings.SitecoreMembershipOptions.ConnectionString = $connectionString

				$originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $appSettingsPath						
			}
			'SitecoreBizFx' {
				Write-Host
				# Copying the BizFx content
				Write-Host "Copying the BizFx content $ServicesContentPath to $PhysicalPath" -ForegroundColor Yellow ;
				Copy-Item -Path $ServicesContentPath -Destination $PhysicalPath -Force -Recurse
				Write-Host "BizFx copy completed" -ForegroundColor Green ;	
                if ($CommerceAuthoringServicesPort -ne "5000") {
                    $pathToJson  = $(Join-Path -Path $PhysicalPath -ChildPath "assets\config.json")
				    $originalJson = Get-Content $pathToJson -Raw  | ConvertFrom-Json
				    $originalJson.EngineUri = $originalJson.EngineUri.replace("5000", $CommerceAuthoringServicesPort)                    
					$originalJson.EnvironmentName = $EnvironmentName                  
				    $originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $pathToJson
                }			
			}
        }
    }
    catch {
        Write-Error $_
    }
}


Function Invoke-CreatePerformanceCountersTask {   

    try {
		$countersVersion = "1.0.2"
        $ccdTypeName = "System.Diagnostics.CounterCreationData"       
        $perfCounterCategoryName = "SitecoreCommerceEngine-$countersVersion"
        $perfCounterInformation = "Performance Counters for Sitecore Commerce Engine"
        $commandCountersName = "SitecoreCommerceCommands-$countersVersion"
        $metricsCountersName = "SitecoreCommerceMetrics-$countersVersion"
        $listCountersName = "SitecoreCommerceLists-$countersVersion"
        $counterCollectionName = "SitecoreCommerceCounters-$countersVersion"
        [array]$allCounters = $commandCountersName,$metricsCountersName,$listCountersName,$counterCollectionName

        Write-Host "Attempting to delete existing Sitecore Commmerce Engine performance counters"

        # delete all counters
        foreach($counter in $allCounters)
        {
	        $categoryExists = [System.Diagnostics.PerformanceCounterCategory]::Exists($counter)
	        If ($categoryExists)
	        {
		        Write-Host "Deleting performance counters $counter" -ForegroundColor Green
		        [System.Diagnostics.PerformanceCounterCategory]::Delete($counter); 
	        }
	        Else
	        {
		        Write-Warning "$counter does not exist, no need to delete"
	        }
        }

        Write-Host "`nAttempting to create Sitecore Commmerce Engine performance counters"

        # command counters
        Write-Host "`nCreating $commandCountersName performance counters" -ForegroundColor Green
        $CounterCommandCollection = New-Object System.Diagnostics.CounterCreationDataCollection
        $CounterCommandCollection.Add( (New-Object $ccdTypeName "CommandsRun", "Number of times a Command has been run", NumberOfItems32) )
        $CounterCommandCollection.Add( (New-Object $ccdTypeName "CommandRun", "Command Process Time (ms)", NumberOfItems32) )
        $CounterCommandCollection.Add( (New-Object $ccdTypeName "CommandRunAverage", "Average of time (ms) for a Command to Process", AverageCount64) )
        $CounterCommandCollection.Add( (New-Object $ccdTypeName "CommandRunAverageBase", "Average of time (ms) for a Command to Process Base", AverageBase) )
        [System.Diagnostics.PerformanceCounterCategory]::Create($commandCountersName, $perfCounterInformation, [Diagnostics.PerformanceCounterCategoryType]::MultiInstance, $CounterCommandCollection) | out-null

        # metrics counters
        Write-Host "`nCreating $metricsCountersName performance counters" -ForegroundColor Green
        $CounterMetricCollection = New-Object System.Diagnostics.CounterCreationDataCollection
        $CounterMetricCollection.Add( (New-Object $ccdTypeName "MetricCount", "Count of Metrics", NumberOfItems32) )
        $CounterMetricCollection.Add( (New-Object $ccdTypeName "MetricAverage", "Average of time (ms) for a Metric", AverageCount64) )
        $CounterMetricCollection.Add( (New-Object $ccdTypeName "MetricAverageBase", "Average of time (ms) for a Metric Base", AverageBase) )
        [System.Diagnostics.PerformanceCounterCategory]::Create($metricsCountersName, $perfCounterInformation, [Diagnostics.PerformanceCounterCategoryType]::MultiInstance, $CounterMetricCollection) | out-null

        # list counters
        Write-Host "`nCreating $listCountersName performance counters" -ForegroundColor Green
        $ListCounterCollection = New-Object System.Diagnostics.CounterCreationDataCollection
        $ListCounterCollection.Add( (New-Object $ccdTypeName "ListCount", "Count of Items in the CommerceList", NumberOfItems32) )
        [System.Diagnostics.PerformanceCounterCategory]::Create($listCountersName, $perfCounterInformation, [Diagnostics.PerformanceCounterCategoryType]::MultiInstance, $ListCounterCollection) | out-null

        # counter collection
        Write-Host "`nCreating $counterCollectionName performance counters" -ForegroundColor Green
        $CounterCollection = New-Object System.Diagnostics.CounterCreationDataCollection
        $CounterCollection.Add( (New-Object $ccdTypeName "ListItemProcess", "Average of time (ms) for List Item to Process", AverageCount64) )
        $CounterCollection.Add( (New-Object $ccdTypeName "ListItemProcessBase", "Average of time (ms) for a List Item to Process Base", AverageBase) )
        [System.Diagnostics.PerformanceCounterCategory]::Create($counterCollectionName, $perfCounterInformation, [Diagnostics.PerformanceCounterCategoryType]::MultiInstance, $CounterCollection) | out-null          
    }
    catch {
        Write-Error $_
    }
}

Register-SitecoreInstallExtension -Command Invoke-DeployCommerceContentTask -As DeployCommerceContent -Type Task -Force

Register-SitecoreInstallExtension -Command Invoke-CreatePerformanceCountersTask -As CreatePerformanceCounters -Type Task -Force

function RenameMessage([string] $oldFile, [string] $newFile){
    Write-Host "Renaming " -nonewline;
    Write-Host "$($oldFile) " -nonewline -ForegroundColor Yellow;
    Write-Host "to " -nonewline;
    Write-Host "$($newFile)" -ForegroundColor Green;
}

function GrantFullReadWriteAccessToFile 
{

PARAM
  (
    [String]$Path=$(throw 'Parameter -Path is missing!'),
    [String]$UserName=$(throw 'Parameter -UserName is missing!')
  )
  Trap
  {
    Write-Host "Error: $($_.Exception.GetType().FullName)" -ForegroundColor Red ; 
    Write-Host $_.Exception.Message; 
    Write-Host $_.Exception.StackTrack;
    break;
  }
  
  $colRights = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [System.Security.AccessControl.FileSystemRights]::Modify;
  #$InheritanceFlag = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit;
  #$PropagationFlag = [System.Security.AccessControl.PropagationFlags]::None;
  $objType =[System.Security.AccessControl.AccessControlType]::Allow;
  
  $Acl = (Get-Item $Path).GetAccessControl("Access");
  $Ar = New-Object system.security.accesscontrol.filesystemaccessrule($UserName, $colRights, $objType);

  for ($i=1; $i -lt 30; $i++)
  {
      try
      {
        Write-Host "Attempt $i to set permissions GrantFullReadWriteAccessToFile"
        $Acl.SetAccessRule($Ar);
        Set-Acl $path $Acl;
        break;
      }
      catch
      {
        Write-Host "Attempt to set permissions failed. Error: $($_.Exception.GetType().FullName)" -ForegroundColor Yellow ; 
        Write-Host $_.Exception.Message; 
        Write-Host $_.Exception.StackTrack;
    
        Write-Host "Retrying command in 10 seconds" -ForegroundColor Yellow ;

        Start-Sleep -Seconds 10
      }
  }
}
