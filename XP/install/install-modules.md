Ensure your assets.json file is up to date.
Run `set-installation-defaults.ps1` and `set-installation-overrides.ps1` to generate a valid `configuration-xp0.json` file

> Note that only Sitecore Powershell Extensions and Sitecore Experience Accelerator have been added to the `module-master-install.json` configuration file (located in Shared\assets\configuration)
> 

After you call `install-modules.ps1` the following occurs:

- **Pre-installation**
  - **Remove** core and master **database users**
  - **Stop xConnect**
  - **Kill** any remaining **connections** to Core and master databases (workaround)
    - InstallWDP requires Database Containement to be set to None. In doing so, it needs exclusive access to the Database in order to make that change. Killing any remaining open connections ensures the installation will succeed
  - **Install Bootloader**: Bootloader is used to apply transforms and poststeps packaged with the Sitecore wdp (scwdp)
- **Download** latest module based on assets.json details
  - if not already an scwdp, use Sitecore Azure Toolkit to **convert** it

- **Install Module**
  - The initial PR contains the steps to install Sitecore PowerShell Extensions and Sitecore Experience Accelerator Modules
- **Post Installation**
  - Enable Contained Databases
  - Add Database Users
  - Start Services
  - Warmup site
  - Configure SXA indexes + populate schemas

The entire process of installation takes under 6 minutes. There are new SIF concepts introduced to this repo:
- AutoRegisterExtensions
  - Use _most_ PowerShell CmdLets directly in the config files (ie: Test-Path, Resolve-Path)
- Nested configurations using Includes

