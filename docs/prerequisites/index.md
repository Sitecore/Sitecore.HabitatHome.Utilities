# Installation of prerequisites

## Preparation

- Open PowerShell session as Administrator
- Ensure correct [ExecutionPolicy](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-6) is set  for unsigned scripts

**example:** `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser`

## Installing Prerequisites

```powershell
    $Global:ProgressPreference = 'SilentlyContinue'
```

> The above will turn off the PowerShell progress bar to **greatly** enhance download speeds

```powershell
    $Global:ProgressPreference = 'Continue'
```

```powershell
.\Install-All.ps1
```

## Restart Computer

Once installation has completed, restart your computer to ensure all settings are loaded correctly.

## Steps Performed by Install-All

### Install Chocolatey

Chocolatey builds on technologies you know - unattended installation and PowerShell. Chocolatey works with all existing software installation technologies like MSI, NSIS, InnoSetup, etc

### Install IIS Features

Uses Windows' native `Enable-WindowsOptionalFeature` to install relevant Windows _IIS Features_ as well as _Url Rewrite_ and _Web Deploy_

### Install Sitecore Gallery

Registers Sitecore's PowerShell repository (Sitecore Gallery) in order to support installing SIF (next step)

### Install Sitecore Install Framework (SIF)

Installs Sitecore Install Framework from the newly registered Sitecore Gallery

### Install Prerequisites

Uses the `prerequisites.json` SIF configuration file supplied to install the known Windows prerequisites for the version of Sitecore you are attempting to install.

The Prerequisites.json file can be found in the XP*Configuration zip package available when downloading Sitecore (OnPrem) from dev.sitecore.com

Ensure you're using the correct version of the Prerequisites.json file. One has been included here as an example but may change with new versions of the product.

## Next Steps

[Installing Sitecore Experience Platform (XP)](../xp/index.md)

[Return to main index](../index.md)
