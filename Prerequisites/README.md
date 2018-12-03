### Suggested Steps for installation of prerequisites

#### Install Sitecore Install Framework (SIF)

- Open PowerShell session as Administrator
```
Install-Package SitecoreInstallFramework -Version 2.0.0 -Source https://sitecore.myget.org/F/sc-powershell/api/v3/index.json
Import-Module SitecoreInstallFramework
```


#### Install Prerequisites

- Create a working directory
	```
	md c:\projects
	Set-Location c:\projects
	```
- Clone the [Sitecore.HabitatHome.Utilities](https://github.com/Sitecore/Sitecore.HabitatHome.Utilities/) repository

	```
	git clone https://github.com/Sitecore/Sitecore.HabitatHome.Utilities.git
	```
	
- Navigate to the XP\install\assets\Configuration folder

```
	Set-Location c:\projects\Sitecore.HabitatHome.Utilities\XP\install\assets\configuration
```

- Turn off PowerShell Progress Bar to greatly enhance download speeds

```
	$Global:ProgressPreference = 'SilentlyContinue'
```
- Install prerequisites
    ```
	Install-SitecoreConfiguration -Path (Resolve-Path .\prerequisites.json)
	```
- Set Progress Bar preferences back to defaults
```
	$Global:ProgressPreference = 'Continue'
	
### RESTART COMPUTER

See the [README.md](../XP/install/README.md) in the XP/install folder for next steps
