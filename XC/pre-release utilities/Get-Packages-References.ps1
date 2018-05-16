$packages = @{
    "packages" = @()
}
$projectFolder = "C:\Projects\Sitecore.Commerce.Engine.SDK.2.2.34"
Get-ChildItem $projectFolder -Filter *.csproj -Recurse | 

Foreach-Object {
    [xml]$content = Get-Content $_.FullName 
     
    foreach ($package in $content.Project.ItemGroup.PackageReference) {
        if ($package.include.length -gt 0) {
            $data = @{Name = $package.Include
                Version = $package.Version 
            }
            $packages.packages += $data
        }
    }
    
}
$packages | ConvertTo-Json -Depth 4 | Out-File  ".\packages.json" -Force
