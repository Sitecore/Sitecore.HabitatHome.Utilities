### Suggested Steps for semi-automated install of prerequisites
#### Boxstarter - install Windows features
- Open PowerShell session as Administrator
- Run Boxstarter bootstrapper (thanks @chiragp) which will install mandatory Windows Features
	`wget -Uri 'https://raw.githubusercontent.com/chiragp/Sitecore-Dev-Machine/master/bootstrap.ps1' -OutFile "$($env:temp)\bootstrap.ps1";&Invoke-Command -ScriptBlock { &"$($env:temp)\bootstrap.ps1" -SkipInstallRecommendedApps}`
#### Install other prerequisites and tools 
- Create a working directory
	`md c:\projects`
	`Set-Location c:\projects`

- Download packages.config from repository

	`Invoke-WebRequest -Uri https://raw.githubusercontent.com/Sitecore/Sitecore.HabitatHome.Utilities/master/Prerequisites/packages.config | set-content packages.config` 

- Review packages.config to ensure it matches what you'd like to install
- Install prerequisites and tools using chocolatey
    `choco install packages.config -y`

- Set the password and enable the SA user (assumes current user has admin privileges)
> You may need to specify the instance name using the -S .\<InstanceName> if you aren't using a default SQL Server instance or if you're using SQLExpress
> Ensure you've installed SQL Server with Mixed Mode authentication (or enable it)

	`$saPassword = "SUPERS3CR3T!!"`
	`sqlcmd -q "ALTER LOGIN [sa] WITH PASSWORD=N'" + $saPassword + "'"`
	`sqlcmd -q "ALTER LOGIN [sa] ENABLE"`

- Clone the [Sitecore.HabitatHome.Utilities](https://github.com/Sitecore/Sitecore.HabitatHome.Utilities/) repository

	`git clone https://github.com/Sitecore/Sitecore.HabitatHome.Utilities.git`

See the [README.md](../XP/install/README.md) in the XP/install folder

	