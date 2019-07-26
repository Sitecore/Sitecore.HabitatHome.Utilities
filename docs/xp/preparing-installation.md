# Preparing Installation Configuration

## Assets

- Review the `assets.json` file to ensure everything is configured correctly.
  - By default, only the SPE and SXA modules get installed automatically. If you would like to install additional modules you will need to set the appropriate flags in this file. See [installing-modules.md](installing-modules.md) for more details.

## Setting up Defaults

- Many settings in the Sitecore XP installation don't need to be changed. `set-installation-defaults.ps1` takes care of the most common settings. Don't worry, you can still override many settings to make the installation your own in the next step!

```powershell
    .\set-installation-defaults.ps1 -packageRepository c:\sitecore-repository
```

### Default Parameters

- `ConfigurationFile`: Specify your own configuration file name if you would like to manage multiple configurations. This is useful when trying to maintain side-by-side Sitecore instances / installations. If you're simply trying to install this for the first time, the default `configuration-xp0.json` file is set.

- `assetsRoot`: does not need to be provided / modified. It will default to `$PSScriptRoot\assets`. Unless you're modifying this for advanced scenarios, leave this one alone.
- `packageRepository`: **Important** - this location is where Sitecore installation assets are downloaded and extracted.
  - If you already have Sitecore assets downloaded you can move them to the location you specify here.
  - It is also the location where you should place your `license.xml` file.
  - **NOTE:** - script will extract package content to the packageRepository location. Ensure the location you choose is acceptable.
- `sitecoreVersion`: Also can be ignored. This is normally set during branching / upgrade and shouldn't need to be modified.

### License File

- Copy your license file to the `packageRepository` folder you specified above

```powershell
    copy license.xml c:\sitecore-repository
```

## Overriding Default Settings

Now that we have some defaults configured, let's override some settings to match your local configuration.

- Make a copy of `set-installation-overrides.ps1.example` file and rename it to remove the .example extension ie: `set-installation-overrides.ps1`.

```powershell
    copy set-installation-overrides.ps1.example set-installation-overrides.ps1
```

> We avoid simply renaming the file from .example to .ps1 since it causes changes in source control.

- Edit **`set-installation-overrides.ps1`** to set the Site, Solr and SQL settings relevant to your environment.

- Apply overrides

```powershell
    .\set-installation-overrides.ps1
```

> NOTE: Remember to always execute `set-installation-defaults.ps1` prior to executing `set-installation-overrides.ps1`

### Override Parameters

- `ConfigurationFile`: Specify the configuration file you've set when calling `set-installation-defaults.ps1` or don't specify if you left the default (`configuration-xp0.json`).

- `prefix`: What would you like to call your site. The default is _habitathome_ but it can be anything you want.
  > **Note**: the default suffix is **dev.local**. Your site will be **_your-prefix_**.dev.local
- `assetsJsonPath`: The default is `assets.json` but this allows you to create your own list of assets.json files to be used.

[Continue to Next Step (Installing Sitecore XP)](installing-sitecore-xp.md)

[Return to Index](readme.md)
