
Function Invoke-DeployCommerceContentTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$ServicesContentPath,
        [Parameter(Mandatory = $true)]
        [string]$PhysicalPath,        
        [Parameter(Mandatory = $true)]
        [string]$UserName, 
        [Parameter(Mandatory = $false)]
        [psobject[]]$BraintreeAccount = @(),        
        [Parameter(Mandatory = $false)]
        [string]$CommerceSearchProvider,
        [Parameter(Mandatory = $false)]
        [string]$SitecoreDbServer,
        [Parameter(Mandatory = $false)]
        [string]$SitecoreCoreDbName,
        [Parameter(Mandatory = $false)]
        [string]$CommerceServicesDbServer,
        [Parameter(Mandatory = $false)]
        [string]$CommerceServicesDbName,
        [Parameter(Mandatory = $false)]
        [string]$CommerceServicesGlobalDbName,
        [Parameter(Mandatory = $false)]
        [string]$SiteHostHeaderName,
        [Parameter(Mandatory = $false)]
        [string]$CommerceAuthoringServicesPort,
        [Parameter(Mandatory = $false)]
        [string]$SitecoreBizFxPort,
        [Parameter(Mandatory = $false)]
        [string]$SolrUrl,
        [Parameter(Mandatory = $false)]
        [string]$SearchIndexPrefix,	
        [Parameter(Mandatory = $false)]
        [string]$EnvironmentsPrefix,		
        [Parameter(Mandatory = $false)]
        [string]$AzureSearchServiceName,		
        [Parameter(Mandatory = $false)]
        [string]$AzureSearchAdminKey,		
        [Parameter(Mandatory = $false)]
        [string]$AzureSearchQueryKey		
    )

    try {       
        switch ($Name) {
            {($_ -match "CommerceOps")} {                    
                Write-Host
                $global:opsServicePath = "$PhysicalPath\*"
                $commerceServicesItem = Get-Item $ServicesContentPath | select-object -first 1

                if (Test-Path $commerceServicesItem -PathType Leaf) {
                    # Assume path to zip file passed in, extract zip to $PhysicalPath
                    #Extracting the CommerceServices zip file Commerce Shops Services
                    Write-Host "Extracting CommerceServices from $commerceServicesItem to $PhysicalPath" -ForegroundColor Yellow ;
                    Expand-Archive $commerceServicesItem -DestinationPath $PhysicalPath -Force
                    Write-Host "CommerceOps Services extraction completed" -ForegroundColor Green ;	
                }
                else {
                    # Assume path is to a published Commerce Engine folder. Copy the contents of the folder to the $PhysicalPath
                    Write-Host "Copying the contents of CommerceServices from $commerceServicesItem to $PhysicalPath" -ForegroundColor Yellow ;
                    Get-ChildItem $ServicesContentPath | Copy-item -Destination $PhysicalPath -Container -Recurse
                    Write-Host "CommerceOps Services copy completed" -ForegroundColor Green ;	
                }               			

                $commerceServicesLogDir = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\logs")                
                if (-not (Test-Path -Path $commerceServicesLogDir)) {                      
                    Write-Host "Creating Commerce Services logs directory at: $commerceServicesLogDir"
                    New-Item -Path $PhysicalPath -Name "wwwroot\logs" -ItemType "directory"
                }

                Write-Host "Granting full access to $UserName to logs directory: $commerceServicesLogDir"
                GrantFullReadWriteAccessToFile -Path $commerceServicesLogDir  -UserName "$($UserName)"							

                # Set the proper environment name                
                $pathToJson = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\config.json")
                $originalJson = Get-Content $pathToJson -Raw  | ConvertFrom-Json
                $originalJson.AppSettings.EnvironmentName = "$($EnvironmentsPrefix)Authoring"
                $allowedOrigins = @("https://localhost:$SitecoreBizFxPort", "https://$SiteHostHeaderName")
                $originalJson.AppSettings.AllowedOrigins = $allowedOrigins 
                
                $originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $pathToJson

                #Replace database name in Global.json
                $pathToGlobalJson = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\bootstrap\Global.json")
                $originalJson = Get-Content $pathToGlobalJson -Raw  | ConvertFrom-Json
                foreach ($p in $originalJson.Policies.'$values') {
                    if ($p.'$type' -eq 'Sitecore.Commerce.Plugin.SQL.EntityStoreSqlPolicy, Sitecore.Commerce.Plugin.SQL') {						
                        $oldServer = $p.Server
                        $oldDatabase = $p.Database
                        $p.Server = $CommerceServicesDbServer
                        $p.Database = $CommerceServicesGlobalDbName
                        Write-Host "Replacing in EntityStoreSqlPolicy $oldServer with $CommerceServicesDbServer and $oldDatabase with $CommerceServicesGlobalDbName"
                    }
                    elseif ($p.'$type' -eq 'Sitecore.Commerce.Plugin.Management.SitecoreConnectionPolicy, Sitecore.Commerce.Plugin.Management') {
                        if ($SiteHostHeaderName -ne "sxa.storefront.com") {
                            $p.Host = $SiteHostHeaderName	
                            Write-Host "Replacing in SitecoreConnectionPolicy 'sxa.storefront.com' with $SiteHostHeaderName"
                        }
                    }
                }
                $originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $pathToGlobalJson
				
                $pathToEnvironmentFiles = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\data\Environments")

                # if setting up Azure search provider we need to rename the azure and solr files
                if ($CommerceSearchProvider -eq 'AZURE') {

                    #rename the azure file from .disabled and disable the Solr policy file
                    $AzurePolicyFile = Get-ChildItem "$pathToEnvironmentFiles\PlugIn.Search.Azure.PolicySet*.disabled"
                    $SolrPolicyFile = Get-ChildItem "$pathToEnvironmentFiles\PlugIn.Search.Solr.PolicySet*.json"
                    $newName = $AzurePolicyFile.FullName -replace ".disabled", ''
                    RenameMessage $($AzurePolicyFile.FullName) $($newName);
                    Rename-Item $AzurePolicyFile -NewName $newName -f;
                    $newName = $SolrPolicyFile.FullName -replace ".json", '.json.disabled'
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
                            $p.Database = $CommerceServicesDbName
                            Write-Host "Replacing in EntityStoreSqlPolicy $oldServer with $CommerceServicesDbServer and $oldDatabase with $CommerceServicesDbName"
                        }
                        elseif ($p.'$type' -eq 'Sitecore.Commerce.Plugin.Management.SitecoreConnectionPolicy, Sitecore.Commerce.Plugin.Management') {
                            if ($SiteHostHeaderName -ne "sxa.storefront.com") {
                                $oldHost = $p.Host;
                                $Writejson = $true
                                $p.Host = $SiteHostHeaderName
                                Write-Host "Replacing SiteHostHeaderName $oldHost with $SiteHostHeaderName"
                            }
                        }
                        elseif ($p.'$type' -eq 'Sitecore.Commerce.Plugin.Search.Solr.SolrSearchPolicy, Sitecore.Commerce.Plugin.Search.Solr') {
                            $p.SolrUrl = $SolrUrl;
                            $Writejson = $true;
                            Write-Host "Replacing Solr Url"
                        }
                        elseif ($p.'$type' -eq 'Sitecore.Commerce.Plugin.Search.Azure.AzureSearchPolicy, Sitecore.Commerce.Plugin.Search.Azure') {
                            $p.SearchServiceName = $AzureSearchServiceName;
                            $p.SearchServiceAdminApiKey = $AzureSearchAdminKey;
                            $p.SearchServiceQueryApiKey = $AzureSearchQueryKey;
                            $Writejson = $true;
                            Write-Host "Replacing Azure service information"
                        }
                        elseif ($p.'$type' -eq 'Plugin.Sample.Payments.Braintree.BraintreeClientPolicy, Plugin.Sample.Payments.Braintree') {
                            $p.MerchantId = $BraintreeAccount.MerchantId;
                            $p.PublicKey = $BraintreeAccount.PublicKey;
                            $p.PrivateKey = $BraintreeAccount.PrivateKey;
                            $Writejson = $true;
                            Write-Host "Inserting Braintree account"
                        }
                        elseif ($p.'$type' -eq 'Sitecore.Commerce.Core.PolicySetPolicy, Sitecore.Commerce.Core' -And $p.'PolicySetId' -eq 'Entity-PolicySet-SolrSearchPolicySet') {
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

                        if ($p.'$type' -eq 'Sitecore.Commerce.Plugin.Search.SearchScopePolicy, Sitecore.Commerce.Plugin.Search') {
                            $oldName = $p.Name
                            $name = "$SearchIndexPrefix$oldName"
                            $p.Name = $name;
                            $Writejson = $true;

                            Write-Host "Replacing SearchScopePolicy Name $oldName with $name"
                        }

                        if ($p.'$type' -eq 'Sitecore.Commerce.Plugin.Search.IndexablePolicy, Sitecore.Commerce.Plugin.Search') {
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
            {($_ -match "CommerceShops") -or ($_ -match "CommerceAuthoring") -or ($_ -match "CommerceMinions")} {
                # Copy the the CommerceServices files to the $Name Services
                Write-Host "Copying Commerce Services from $global:opsServicePath to $PhysicalPath" -ForegroundColor Yellow ;
                Get-ChildItem $global:opsServicePath | Copy-item -Destination $PhysicalPath -Container -Recurse

                Write-Host "$($_) Services extraction completed" -ForegroundColor Green ;

                $commerceServicesLogDir = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\logs")
                if (-not (Test-Path -Path $commerceServicesLogDir)) {                      
                    Write-Host "Creating Commerce Services logs directory at: $commerceServicesLogDir"
                    New-Item -Path $PhysicalPath -Name "wwwroot\logs" -ItemType "directory"
                }
				
                Write-Host "Granting full access to $UserName to logs directory: $commerceServicesLogDir"
                GrantFullReadWriteAccessToFile -Path $commerceServicesLogDir  -UserName "$($UserName)"

                # Set the proper environment name
                $pathToJson = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\config.json")
                $originalJson = Get-Content $pathToJson -Raw | ConvertFrom-Json
				
                $environment = "$($EnvironmentsPrefix)Shops"
                if ($Name -match "CommerceAuthoring") {
                    $environment = "$($EnvironmentsPrefix)Authoring"
                }
                elseif ($Name -match "CommerceMinions") {
                    $environment = "$($EnvironmentsPrefix)Minions"
                }		
                $originalJson.AppSettings.EnvironmentName = $environment
                $originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $pathToJson
            }               
            {($_ -match "IdentityServer")} {
                Write-Host
                # Extracting Sitecore.IdentityServer zip file
                $commerceServicesItem = Get-Item $ServicesContentPath | select-object -first 1

                if (Test-Path $commerceServicesItem -PathType Leaf) {
                    # Assume path to zip file passed in, extract zip to $PhysicalPath
                    #Extracting the CommerceServices zip file Commerce Shops Services
                    Write-Host "Extracting Sitecore.IdentityServer from $commerceServicesItem to $PhysicalPath" -ForegroundColor Yellow ;
                    Expand-Archive $commerceServicesItem -DestinationPath $PhysicalPath -Force
                    Write-Host "Sitecore.IdentityServer extraction completed" -ForegroundColor Green ;
                }
                else {
                    # Assume path is to a published Sitecore Identity Server folder. Copy the contents of the folder to the $PhysicalPath
                    Write-Host "Copying the contents of Sitecore Identity Server from $commerceServicesItem to $PhysicalPath" -ForegroundColor Yellow ;
                    Get-ChildItem $ServicesContentPath | Copy-item -Destination $PhysicalPath -Container -Recurse
                    Write-Host "Sitecore.IdentityServer copy completed" -ForegroundColor Green ;
                }

                $commerceServicesLogDir = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\logs")
                if (-not (Test-Path -Path $commerceServicesLogDir)) {                      
                    Write-Host "Creating Commerce Services logs directory at: $commerceServicesLogDir"
                    New-Item -Path $PhysicalPath -Name "wwwroot\logs" -ItemType "directory"
                }
				
                Write-Host "Granting full access to $UserName to logs directory: $commerceServicesLogDir"
                GrantFullReadWriteAccessToFile -Path $commerceServicesLogDir  -UserName "$($UserName)"
				
                $appSettingsPath = $(Join-Path -Path $PhysicalPath -ChildPath "wwwroot\appsettings.json")
                $originalJson = Get-Content $appSettingsPath -Raw | ConvertFrom-Json
                $connectionString = $originalJson.AppSettings.SitecoreMembershipOptions.ConnectionString
                $connectionString = $connectionString -replace "SXAStorefrontSitecore_Core", $SitecoreCoreDbName
                $connectionString = $connectionString -replace "localhost", $SitecoreDbServer
                $originalJson.AppSettings.SitecoreMembershipOptions.ConnectionString = $connectionString

                if ($SitecoreBizFxPort -ne "4200") {
                    $client = $originalJson.AppSettings.Clients[0]
                    $Uris = @()
                    for ($i = 0; $i -lt $client.RedirectUris.Count ; $i++) {
                        $find = $originalJson.AppSettings.Clients.RedirectUris[$i]
                        $Uris += $find -replace "4200", $SitecoreBizFxPort                            
                    }
                    $originalJson.AppSettings.Clients[0].RedirectUris = $Uris

                    $Uris1 = @()
                    for ($i = 0; $i -lt $client.PostLogoutRedirectUris.Count ; $i++) {
                        $find = $originalJson.AppSettings.Clients.PostLogoutRedirectUris[$i]
                        $Uris1 += $find -replace "4200", $SitecoreBizFxPort                            
                    }
                    $originalJson.AppSettings.Clients[0].PostLogoutRedirectUris = $Uris1
					  
                    $Uris2 = @()
                    for ($i = 0; $i -lt $client.AllowedCorsOrigins.Count ; $i++) {
                        $find = $originalJson.AppSettings.Clients.AllowedCorsOrigins[$i]
                        $Uris2 += $find -replace "4200", $SitecoreBizFxPort                            
                    }
                    $originalJson.AppSettings.Clients[0].AllowedCorsOrigins = $Uris2
                }

                $originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $appSettingsPath						
            }
            {($_ -match "BizFx")} {
                Write-Host
                # Copying the BizFx content
                $commerceServicesItem = Get-Item $ServicesContentPath | select-object -first 1
                if (Test-Path $commerceServicesItem -PathType Leaf) {
                    # Assume path to zip file passed in, extract zip to $PhysicalPath
                    #Extracting the BizFx zip file 
                    Write-Host "Extracting BizFx from $commerceServicesItem to $PhysicalPath" -ForegroundColor Yellow ;
                    Expand-Archive $commerceServicesItem -DestinationPath $PhysicalPath -Force
                    Write-Host "SitecoreBizFx extraction completed" -ForegroundColor Green ;
                }
                else {
                    # Assume path is to a published BizFx folder. Copy the contents of the folder to the $PhysicalPath
                    Write-Host "Copying the BizFx content $ServicesContentPath to $PhysicalPath" -ForegroundColor Yellow ;
                    Get-ChildItem $ServicesContentPath | Copy-item -Destination $PhysicalPath -Container -Recurse 
                    Write-Host "SitecoreBizFx copy completed" -ForegroundColor Green ;
                }
				
                $pathToJson = $(Join-Path -Path $PhysicalPath -ChildPath "assets\config.json")
                $originalJson = Get-Content $pathToJson -Raw  | ConvertFrom-Json
                $originalJson.EngineUri = $originalJson.EngineUri -replace "5000", $CommerceAuthoringServicesPort
                $originalJson.BizFxUri = $originalJson.BizFxUri -replace "4200", $SitecoreBizFxPort  
                  
                $originalJson | ConvertTo-Json -Depth 100 -Compress | set-content $pathToJson                			
            }			
            default { Write-Host "Create content failed for $($_). Name $($_) is unknown" }
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
        [array]$allCounters = $commandCountersName, $metricsCountersName, $listCountersName, $counterCollectionName

        Write-Host "Attempting to delete existing Sitecore Commmerce Engine performance counters"

        # delete all counters
        foreach ($counter in $allCounters) {
            $categoryExists = [System.Diagnostics.PerformanceCounterCategory]::Exists($counter)
            If ($categoryExists) {
                Write-Host "Deleting performance counters $counter" -ForegroundColor Green
                [System.Diagnostics.PerformanceCounterCategory]::Delete($counter); 
            }
            Else {
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

function RenameMessage([string] $oldFile, [string] $newFile) {
    Write-Host "Renaming " -nonewline;
    Write-Host "$($oldFile) " -nonewline -ForegroundColor Yellow;
    Write-Host "to " -nonewline;
    Write-Host "$($newFile)" -ForegroundColor Green;
}

function GrantFullReadWriteAccessToFile {

    PARAM
    (
        [String]$Path = $(throw 'Parameter -Path is missing!'),
        [String]$UserName = $(throw 'Parameter -UserName is missing!')
    )
    Trap {
        Write-Host "Error: $($_.Exception.GetType().FullName)" -ForegroundColor Red ; 
        Write-Host $_.Exception.Message; 
        Write-Host $_.Exception.StackTrack;
        break;
    }
  
    $colRights = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [System.Security.AccessControl.FileSystemRights]::Modify;
    #$InheritanceFlag = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit;
    #$PropagationFlag = [System.Security.AccessControl.PropagationFlags]::None;
    $objType = [System.Security.AccessControl.AccessControlType]::Allow;
  
    $Acl = (Get-Item $Path).GetAccessControl("Access");
    $Ar = New-Object system.security.accesscontrol.filesystemaccessrule($UserName, $colRights, $objType);

    for ($i = 1; $i -lt 30; $i++) {
        try {
            Write-Host "Attempt $i to set permissions GrantFullReadWriteAccessToFile"
            $Acl.SetAccessRule($Ar);
            Set-Acl $path $Acl;
            break;
        }
        catch {
            Write-Host "Attempt to set permissions failed. Error: $($_.Exception.GetType().FullName)" -ForegroundColor Yellow ; 
            Write-Host $_.Exception.Message; 
            Write-Host $_.Exception.StackTrack;
    
            Write-Host "Retrying command in 10 seconds" -ForegroundColor Yellow ;

            Start-Sleep -Seconds 10
        }
    }
}
# SIG # Begin signature block
# MIIXwQYJKoZIhvcNAQcCoIIXsjCCF64CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU7nLq3Y1YO+2siU1IYo7ksJBW
# AYmgghL8MIID7jCCA1egAwIBAgIQfpPr+3zGTlnqS5p31Ab8OzANBgkqhkiG9w0B
# AQUFADCBizELMAkGA1UEBhMCWkExFTATBgNVBAgTDFdlc3Rlcm4gQ2FwZTEUMBIG
# A1UEBxMLRHVyYmFudmlsbGUxDzANBgNVBAoTBlRoYXd0ZTEdMBsGA1UECxMUVGhh
# d3RlIENlcnRpZmljYXRpb24xHzAdBgNVBAMTFlRoYXd0ZSBUaW1lc3RhbXBpbmcg
# Q0EwHhcNMTIxMjIxMDAwMDAwWhcNMjAxMjMwMjM1OTU5WjBeMQswCQYDVQQGEwJV
# UzEdMBsGA1UEChMUU3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFu
# dGVjIFRpbWUgU3RhbXBpbmcgU2VydmljZXMgQ0EgLSBHMjCCASIwDQYJKoZIhvcN
# AQEBBQADggEPADCCAQoCggEBALGss0lUS5ccEgrYJXmRIlcqb9y4JsRDc2vCvy5Q
# WvsUwnaOQwElQ7Sh4kX06Ld7w3TMIte0lAAC903tv7S3RCRrzV9FO9FEzkMScxeC
# i2m0K8uZHqxyGyZNcR+xMd37UWECU6aq9UksBXhFpS+JzueZ5/6M4lc/PcaS3Er4
# ezPkeQr78HWIQZz/xQNRmarXbJ+TaYdlKYOFwmAUxMjJOxTawIHwHw103pIiq8r3
# +3R8J+b3Sht/p8OeLa6K6qbmqicWfWH3mHERvOJQoUvlXfrlDqcsn6plINPYlujI
# fKVOSET/GeJEB5IL12iEgF1qeGRFzWBGflTBE3zFefHJwXECAwEAAaOB+jCB9zAd
# BgNVHQ4EFgQUX5r1blzMzHSa1N197z/b7EyALt0wMgYIKwYBBQUHAQEEJjAkMCIG
# CCsGAQUFBzABhhZodHRwOi8vb2NzcC50aGF3dGUuY29tMBIGA1UdEwEB/wQIMAYB
# Af8CAQAwPwYDVR0fBDgwNjA0oDKgMIYuaHR0cDovL2NybC50aGF3dGUuY29tL1Ro
# YXd0ZVRpbWVzdGFtcGluZ0NBLmNybDATBgNVHSUEDDAKBggrBgEFBQcDCDAOBgNV
# HQ8BAf8EBAMCAQYwKAYDVR0RBCEwH6QdMBsxGTAXBgNVBAMTEFRpbWVTdGFtcC0y
# MDQ4LTEwDQYJKoZIhvcNAQEFBQADgYEAAwmbj3nvf1kwqu9otfrjCR27T4IGXTdf
# plKfFo3qHJIJRG71betYfDDo+WmNI3MLEm9Hqa45EfgqsZuwGsOO61mWAK3ODE2y
# 0DGmCFwqevzieh1XTKhlGOl5QGIllm7HxzdqgyEIjkHq3dlXPx13SYcqFgZepjhq
# IhKjURmDfrYwggSjMIIDi6ADAgECAhAOz/Q4yP6/NW4E2GqYGxpQMA0GCSqGSIb3
# DQEBBQUAMF4xCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3Jh
# dGlvbjEwMC4GA1UEAxMnU3ltYW50ZWMgVGltZSBTdGFtcGluZyBTZXJ2aWNlcyBD
# QSAtIEcyMB4XDTEyMTAxODAwMDAwMFoXDTIwMTIyOTIzNTk1OVowYjELMAkGA1UE
# BhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMTQwMgYDVQQDEytT
# eW1hbnRlYyBUaW1lIFN0YW1waW5nIFNlcnZpY2VzIFNpZ25lciAtIEc0MIIBIjAN
# BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAomMLOUS4uyOnREm7Dv+h8GEKU5Ow
# mNutLA9KxW7/hjxTVQ8VzgQ/K/2plpbZvmF5C1vJTIZ25eBDSyKV7sIrQ8Gf2Gi0
# jkBP7oU4uRHFI/JkWPAVMm9OV6GuiKQC1yoezUvh3WPVF4kyW7BemVqonShQDhfu
# ltthO0VRHc8SVguSR/yrrvZmPUescHLnkudfzRC5xINklBm9JYDh6NIipdC6Anqh
# d5NbZcPuF3S8QYYq3AhMjJKMkS2ed0QfaNaodHfbDlsyi1aLM73ZY8hJnTrFxeoz
# C9Lxoxv0i77Zs1eLO94Ep3oisiSuLsdwxb5OgyYI+wu9qU+ZCOEQKHKqzQIDAQAB
# o4IBVzCCAVMwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAO
# BgNVHQ8BAf8EBAMCB4AwcwYIKwYBBQUHAQEEZzBlMCoGCCsGAQUFBzABhh5odHRw
# Oi8vdHMtb2NzcC53cy5zeW1hbnRlYy5jb20wNwYIKwYBBQUHMAKGK2h0dHA6Ly90
# cy1haWEud3Muc3ltYW50ZWMuY29tL3Rzcy1jYS1nMi5jZXIwPAYDVR0fBDUwMzAx
# oC+gLYYraHR0cDovL3RzLWNybC53cy5zeW1hbnRlYy5jb20vdHNzLWNhLWcyLmNy
# bDAoBgNVHREEITAfpB0wGzEZMBcGA1UEAxMQVGltZVN0YW1wLTIwNDgtMjAdBgNV
# HQ4EFgQURsZpow5KFB7VTNpSYxc/Xja8DeYwHwYDVR0jBBgwFoAUX5r1blzMzHSa
# 1N197z/b7EyALt0wDQYJKoZIhvcNAQEFBQADggEBAHg7tJEqAEzwj2IwN3ijhCcH
# bxiy3iXcoNSUA6qGTiWfmkADHN3O43nLIWgG2rYytG2/9CwmYzPkSWRtDebDZw73
# BaQ1bHyJFsbpst+y6d0gxnEPzZV03LZc3r03H0N45ni1zSgEIKOq8UvEiCmRDoDR
# EfzdXHZuT14ORUZBbg2w6jiasTraCXEQ/Bx5tIB7rGn0/Zy2DBYr8X9bCT2bW+IW
# yhOBbQAuOA2oKY8s4bL0WqkBrxWcLC9JG9siu8P+eJRRw4axgohd8D20UaF5Mysu
# e7ncIAkTcetqGVvP6KUwVyyJST+5z3/Jvz4iaGNTmr1pdKzFHTx/kuDDvBzYBHUw
# ggUrMIIEE6ADAgECAhAHplztCw0v0TJNgwJhke9VMA0GCSqGSIb3DQEBCwUAMHIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJ
# RCBDb2RlIFNpZ25pbmcgQ0EwHhcNMTcwODIzMDAwMDAwWhcNMjAwOTMwMTIwMDAw
# WjBoMQswCQYDVQQGEwJVUzELMAkGA1UECBMCY2ExEjAQBgNVBAcTCVNhdXNhbGl0
# bzEbMBkGA1UEChMSU2l0ZWNvcmUgVVNBLCBJbmMuMRswGQYDVQQDExJTaXRlY29y
# ZSBVU0EsIEluYy4wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC7PZ/g
# huhrQ/p/0Cg7BRrYjw7ZMx8HNBamEm0El+sedPWYeAAFrjDSpECxYjvK8/NOS9dk
# tC35XL2TREMOJk746mZqia+g+NQDPEaDjNPG/iT0gWsOeCa9dUcIUtnBQ0hBKsuR
# bau3n7w1uIgr3zf29vc9NhCoz1m2uBNIuLBlkKguXwgPt4rzj66+18JV3xyLQJoS
# 3ZAA8k6FnZltNB+4HB0LKpPmF8PmAm5fhwGz6JFTKe+HCBRtuwOEERSd1EN7TGKi
# xczSX8FJMz84dcOfALxjTj6RUF5TNSQLD2pACgYWl8MM0lEtD/1eif7TKMHqaA+s
# m/yJrlKEtOr836BvAgMBAAGjggHFMIIBwTAfBgNVHSMEGDAWgBRaxLl7Kgqjpepx
# A8Bg+S32ZXUOWDAdBgNVHQ4EFgQULh60SWOBOnU9TSFq0c2sWmMdu7EwDgYDVR0P
# AQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGA1UdHwRwMG4wNaAzoDGG
# L2h0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtY3MtZzEuY3Js
# MDWgM6Axhi9odHRwOi8vY3JsNC5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVkLWNz
# LWcxLmNybDBMBgNVHSAERTBDMDcGCWCGSAGG/WwDATAqMCgGCCsGAQUFBwIBFhxo
# dHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAgGBmeBDAEEATCBhAYIKwYBBQUH
# AQEEeDB2MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wTgYI
# KwYBBQUHMAKGQmh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFNI
# QTJBc3N1cmVkSURDb2RlU2lnbmluZ0NBLmNydDAMBgNVHRMBAf8EAjAAMA0GCSqG
# SIb3DQEBCwUAA4IBAQBozpJhBdsaz19E9faa/wtrnssUreKxZVkYQ+NViWeyImc5
# qEZcDPy3Qgf731kVPnYuwi5S0U+qyg5p1CNn/WsvnJsdw8aO0lseadu8PECuHj1Z
# 5w4mi5rGNq+QVYSBB2vBh5Ps5rXuifBFF8YnUyBc2KuWBOCq6MTRN1H2sU5LtOUc
# Qkacv8hyom8DHERbd3mIBkV8fmtAmvwFYOCsXdBHOSwQUvfs53GySrnIYiWT0y56
# mVYPwDj7h/PdWO5hIuZm6n5ohInLig1weiVDJ254r+2pfyyRT+02JVVxyHFMCLwC
# ASs4vgbiZzMDltmoTDHz9gULxu/CfBGM0waMDu3cMIIFMDCCBBigAwIBAgIQBAkY
# G1/Vu2Z1U0O1b5VQCDANBgkqhkiG9w0BAQsFADBlMQswCQYDVQQGEwJVUzEVMBMG
# A1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQw
# IgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMTMxMDIyMTIw
# MDAwWhcNMjgxMDIyMTIwMDAwWjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhE
# aWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMIIBIjANBgkq
# hkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA+NOzHH8OEa9ndwfTCzFJGc/Q+0WZsTrb
# RPV/5aid2zLXcep2nQUut4/6kkPApfmJ1DcZ17aq8JyGpdglrA55KDp+6dFn08b7
# KSfH03sjlOSRI5aQd4L5oYQjZhJUM1B0sSgmuyRpwsJS8hRniolF1C2ho+mILCCV
# rhxKhwjfDPXiTWAYvqrEsq5wMWYzcT6scKKrzn/pfMuSoeU7MRzP6vIK5Fe7SrXp
# dOYr/mzLfnQ5Ng2Q7+S1TqSp6moKq4TzrGdOtcT3jNEgJSPrCGQ+UpbB8g8S9MWO
# D8Gi6CxR93O8vYWxYoNzQYIH5DiLanMg0A9kczyen6Yzqf0Z3yWT0QIDAQABo4IB
# zTCCAckwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0l
# BAwwCgYIKwYBBQUHAwMweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRw
# Oi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwgYEGA1Ud
# HwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFz
# c3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNv
# bS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwTwYDVR0gBEgwRjA4BgpghkgB
# hv1sAAIEMCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9D
# UFMwCgYIYIZIAYb9bAMwHQYDVR0OBBYEFFrEuXsqCqOl6nEDwGD5LfZldQ5YMB8G
# A1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMA0GCSqGSIb3DQEBCwUAA4IB
# AQA+7A1aJLPzItEVyCx8JSl2qB1dHC06GsTvMGHXfgtg/cM9D8Svi/3vKt8gVTew
# 4fbRknUPUbRupY5a4l4kgU4QpO4/cY5jDhNLrddfRHnzNhQGivecRk5c/5CxGwcO
# kRX7uq+1UcKNJK4kxscnKqEpKBo6cSgCPC6Ro8AlEeKcFEehemhor5unXCBc2XGx
# DI+7qPjFEmifz0DLQESlE/DmZAwlCEIysjaKJAL+L3J+HNdJRZboWR3p+nRka7Lr
# ZkPas7CM1ekN3fYBIM6ZMWM9CBoYs4GbT8aTEAb8B4H6i9r5gkn3Ym6hU/oSlBiF
# LpKR6mhsRDKyZqHnGKSaZFHvMYIELzCCBCsCAQEwgYYwcjELMAkGA1UEBhMCVVMx
# FTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNv
# bTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVkIElEIENvZGUgU2lnbmlu
# ZyBDQQIQB6Zc7QsNL9EyTYMCYZHvVTAJBgUrDgMCGgUAoHAwEAYKKwYBBAGCNwIB
# DDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFO8J+cIBkdNUGqa+YMqQYgng
# zAjXMA0GCSqGSIb3DQEBAQUABIIBABpFmItHVHcSPA3ScZaC528194MmD9lBYmad
# iWTDQqoXk+huDIgs5NOhY1yyxOGwykduZObSYssakg1XqKYmdz+Hj84mVr0NDfGP
# sLxENK2VtKh1UR6TQQGoeoikY9Xv1mbA3bgi60L3TF691QvDhgl1izvB36hafIiB
# bHyz2fZtAnOn4tDV+vEdh0zhN5KCHqmvTsXS3EjAG3xBqx2fHAxLAqpJFXy6YXZn
# kdGfKQgubWpMD2HXpbk5culvHJJ4cPmuomN/J16uZ0uMd30CUrFYAo2hk5xBCUoU
# obaqvwWAvQ3HnYrepAVxF5cByrikuZ9W0Hn5v+xbuWum5F8R7VihggILMIICBwYJ
# KoZIhvcNAQkGMYIB+DCCAfQCAQEwcjBeMQswCQYDVQQGEwJVUzEdMBsGA1UEChMU
# U3ltYW50ZWMgQ29ycG9yYXRpb24xMDAuBgNVBAMTJ1N5bWFudGVjIFRpbWUgU3Rh
# bXBpbmcgU2VydmljZXMgQ0EgLSBHMgIQDs/0OMj+vzVuBNhqmBsaUDAJBgUrDgMC
# GgUAoF0wGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MTkwMTA5MTYzNjUzWjAjBgkqhkiG9w0BCQQxFgQUhH0758qS6JW+X60GUNAP8wfy
# xN4wDQYJKoZIhvcNAQEBBQAEggEAZ4E+M08dfXqtC0xdEfu9tViEg2kZowc+K1rQ
# QX0+ei22tICQcw/AZD2LtnyA790ISZpWZPj0xxpUnxM0buSHTCJcL0zwOLMbXxJy
# u4YSjOzr7O2XgfNVNyuk/IRYLJMw+2mJgcRuTw5sUQjxr3DjG3d4+JFCh9gtsUFM
# G9rhUxJuxzYonO8KUqOzTKb7HJuYI94oUlkc4tQffbvTuz3o5ERzbQxBewyyY38/
# kQ1day2bHcHPwPHLD6uQXMQKWH7x3dfSqTrGPKxwLlUTfhAzzVl5c8Yj48BC13gR
# VDDM+jb2nMYaGH7DHH/UOZa/zFQaqPsdz9CIVP8Rfrvytz+kGQ==
# SIG # End signature block
