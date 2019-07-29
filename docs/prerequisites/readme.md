# Installation of prerequisites

## Preparation

- Open PowerShell session as Administrator
- Ensure correct [ExecutionPolicy](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-6) is set  for unsigned scripts

  - **example:** `Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser`

## Installing Prerequisites

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

Uses the `Prerequisites.json` SIF configuration file from the `Prerequisites` folder to install the known Windows prerequisites for the version of Sitecore you are attempting to install.

The `Prerequisites.json` file is coming from the zip package of the Sitecore version to install. It is updated every time this repo is modified to install a different Sitecore version.

## Next Steps

[Installing Sitecore Experience Platform (XP)](../xp/readme.md)

[Return to main docs index](../readme.md)
