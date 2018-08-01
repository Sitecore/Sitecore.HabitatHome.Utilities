Set-Alias -Name Invoke-InstallSitecoreConfigurationTask -Value Install-SitecoreConfiguration


Register-SitecoreInstallExtension -Command Invoke-InstallSitecoreConfigurationTask -As InstallSitecoreConfiguration -Type Task -Force
