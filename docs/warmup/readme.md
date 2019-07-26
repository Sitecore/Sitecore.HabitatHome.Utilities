# Warming up a Sitecore Instance

The `warmup.ps1` script in the Warmup folder makes web requests to an array of urls from the `warmup-config.json` which help pre-compile and cache pages from the Sitecore Base, XP and XC demos. The script will take some time to run but the result should be that all pages listed in the config file will get pre-compiled and cached where applicable.

The `warmup-config.json` file can be customized to suit your needs (add additional backend pages to warmup, etc).

To use, simply call the script and specify whether you want to warm up the base Sitecore backend or the Habitat Home XP or XC demos.

```powershell
.\warmup.ps1 -instance <your-instance-url> -demoType <*sitecore* or *xp* or *xc*> -adminUser <sitecore-admin-user> -adminPassword <sitecore-admin-password>
```

The script is provided as an example and can be modified to suit your needs.

[Return to main docs index](../readme.md)
