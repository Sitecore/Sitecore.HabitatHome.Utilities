# Solr Installation

Solr can be installed with a script if you do not already have it.

## Install Solr

Still in an elevated PowerShell session:

- Browse to the solr folder.

  ```powershell
  Set-Location Sitecore.Habitathome.Utilities\XP\install\Solr
  ```

- Review the `install-solr.ps1` script to ensure the Java and Solr versions are correct.
- Install Solr.

  ```powershell
  .\install-solr.ps1
  ```

- Once setup is complete, the installer should load the solr 'home' page

## To Uninstall Solr

- Review the `remove-solr.ps1` script to ensure the Solr versions and its data folder are correct.
- Uninstall Solr.

  ```powershell
  .\remove-solr.ps1
  ```

## Next Steps

[Continue to Next Step (Preparing for Installation)](preparing-installation.md)

[Return to Index](readme.md)

[Return to main docs index](../readme.md)
