## Installation helpers for Sitecore Experience Commerce (XC)

> These steps assume you have all of the prerequisites installed or have followed the instructions at [Prerequisites README.md](../../Prerequisits/README.md) and [XP Installation README.md](..\..\XP\install\README.md)

Still in an elevated PowerShell session

- Browse to the XC installation folder
  ```
  Set-Location ..\..\XC\install
  ```

- Set some predefined defaults
  ```
  .\set-installation-defaults.ps1
  ```

- Create a copy of the overrides file
  ```
  copy set-installation-overrides.ps1.example set-installation-overrides.ps1
  ```

- Edit **`set-installation-overrides.ps1`** to set the SQL instance name and sa password

- Apply overrides
  ```
	.\set-installation-overrides.ps1
	```

> **KNOWN ISSUE:** Automatic download of assets is current not working as expected.
> 
> **WORKAROUND:** Download the following assets and place them in the indicated folders:
> - [Sitecore.Commerce.2018.07-2.2.126.zip](https://dev.sitecore.net/~/media/F374366CA5C649C99B09D35D5EF1BFCE.ashx) - `xc/install/assets/downloads`
> - [Habitat Home Product Images.zip](https://sitecore.box.com/shared/static/bjvge68eqge87su5vg258366rve6bg5d.zip) - `xc/install/assets/Commerce`

Once the above files have been downloaded:

```
install-xc0.ps1
```

## Troubleshooting

#### Resuming Installation

If a part of the installation fails, you can resume from the last failed step by removing the relevant tasks in the Commerce_SingleServer.json file.

The file is located in `XC\install\assets\Resources`.

Make sure you make a backup copy of the file.