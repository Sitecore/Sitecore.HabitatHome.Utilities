#Requires -Modules WebAdministration

#Set-StrictMode -Version 2.0

Function Invoke-MergeWebConfigTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$MergeTool,		
        [Parameter(Mandatory=$true)]        
		[string]$InputFile,
		[Parameter(Mandatory=$true)]
        [string]$WebConfig			
    )  
	
	Write-Host "Merging: $($InputFile)"
	Write-Host "Merge tool: $($MergeTool)"	
	
	Add-Type -LiteralPath  $MergeTool

    try 
    {
        if (!$WebConfig -or !(Test-Path -path $WebConfig -PathType Leaf)) {
			throw "File not found. $WebConfig";
		}
		if (!$InputFile -or !(Test-Path -path $InputFile -PathType Leaf)) {
			throw "File not found. $InputFile";
		}  

		$xmldoc = New-Object Microsoft.Web.XmlTransform.XmlTransformableDocument;
		$xmldoc.PreserveWhitespace = $true
		$xmldoc.Load($WebConfig);

		$transf = New-Object Microsoft.Web.XmlTransform.XmlTransformation($InputFile);
		if ($transf.Apply($xmldoc) -eq $false)
		{
			throw "Transformation failed."
		}
		$xmldoc.Save($WebConfig);
    }
    catch
    {
        Write-Output $Error[0].Exception
    } 
}

Register-SitecoreInstallExtension -Command Invoke-MergeWebConfigTask -As MergeWebConfig -Type Task -Force
