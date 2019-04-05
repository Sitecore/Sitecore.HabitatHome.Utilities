# Installation of prerequisites



- Open PowerShell session as Administrator

```
.\Install-All.ps1
```

### Steps Performed by Install-All

#### Install Chocolatey
Chocolatey builds on technologies you know - unattended installation and PowerShell. Chocolatey works with all existing software installation technologies like MSI, NSIS, InnoSetup, etc
#### Install IIS Features
Uses Windows' native `Enable-WindowsOptionalFeature` to install relevant Windows **IIS Features **as well as **Url Rewrite** and **Web Deploy**
#### Install Sitecore Gallery
Registers Sitecore's PowerShell repository (Sitecore Gallery) in order to support installing SIF (next step)

#### Install Sitecore Install Framework (SIF)
Installs Sitecore Install Framework from the newly registered Sitecore Gallery

#### Install Prerequisites
Uses the `prerequisites.json` SIF configuration file supplied to install the known Windows prerequisites for the version of Sitecore you are attempting to install.

The Prerequisites.json file can be found in the XP*Configuration zip package available when downloading Sitecore (OnPrem) from dev.sitecore.com

Ensure you're using the correct version of the Prerequisites.json file. One has been included here as an example but may change with new versions of the product.

This will also turn off the PowerShell progress bar to **greatly ** enhance download speeds

```
	$Global:ProgressPreference = 'SilentlyContinue'
```

```
	$Global:ProgressPreference = 'Continue'
```
	
### RESTART COMPUTER

See the [README.md](../XP/install/README.md) in the XP/install folder for next steps
