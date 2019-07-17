# Installing Sitecore XP

This repository only supports XP0 (XPSingle) installation. This means _everything_ is on the same machine (SQL Server (or SQLExpress), Solr, etc.)

We're finally here, prerequisites are installed, configuration is set and now it's the moment of truth!

```powershell
.\install-singledeveloper.ps1
```

> You will be prompted for your dev.sitecore.com credentials - the required assets will be downloaded automatically.

## We're done

> Now go grab a coffee, really...
>
> Should take 12 to 15 minutes depending on your environment.

### What's happening

`install-singledeveloper.ps1` is a wrapper around the OOB `XP0-Singledevloper.ps1` and corresponding `XP0-SingleDeveloper.json` installation process _(although the Utilities repo did bring some enhancements to the OOB configurations)_.

In addition to what the OOB installer will do, `install-singledeveloper.ps1` will:

- Install Sitecore Installation Framework
- Automatically download all required Sitecore assets from dev.sitecore.com (_if they don't already exist_)
- Install Sitecore with SSL configured
- Add AppPool user(s) to_ Performance Log Users_ and _Performance Monitor Users_ groups to avoid errors in the Sitecore log

[Continue to Next Step (Installing Modules)](installing-modules.md)

[Return to Index](index.md)
