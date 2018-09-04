### Suggested Steps for semi-automated install of prerequisites
#### Boxstarter - install Windows features
- Open PowerShell session as Administrator
#### Install other prerequisites and tools 
- Create a working directory
	`md c:\projects`
	`Set-Location c:\projects`

- Download packages.config and install.ps1 from repository

	`Invoke-WebRequest -Uri https://raw.githubusercontent.com/Sitecore/Sitecore.HabitatHome.Utilities/master/Prerequisites/packages.config | set-content packages.config` 
	`Invoke-WebRequest -Uri https://raw.githubusercontent.com/Sitecore/Sitecore.HabitatHome.Utilities/master/Prerequisites/install.ps1 | set-content install.ps1` 

- **Review packages.config** to ensure it matches what you'd like to install
- Install prerequisites and tools
    `.\install.ps1`

- Manually install and configure SQL Server


### RESTART COMPUTER

- Clone the [Sitecore.HabitatHome.Utilities](https://github.com/Sitecore/Sitecore.HabitatHome.Utilities/) repository

	`git clone https://github.com/Sitecore/Sitecore.HabitatHome.Utilities.git`

See the [README.md](../XP/install/README.md) in the XP/install folder

	
