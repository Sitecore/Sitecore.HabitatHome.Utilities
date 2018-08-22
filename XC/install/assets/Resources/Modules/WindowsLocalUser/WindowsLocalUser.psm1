Function Invoke-EnsureLocalUserTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [psobject]$UserAccount   
    )
    
    # Local user 
    $ComputerName = $($UserAccount.Domain)
    try {     
		$objComputer = [ADSI]("WinNT://$ComputerName, computer");
		$colUsers = ($objComputer.psbase.children |
		Where-Object {$_.psBase.schemaClassName -eq "User"} |
		Select-Object -expand Name)

		$blnFound = $colUsers -contains $($UserAccount.UserName)

		if ($blnFound) { 
			Write-Host "The user account exists.";
		}
		else {
			Write-Host "The user account does not exist ... creating user '$UserAccount.UserName'.";
			NewLocalUser -UserName $($UserAccount.UserName) -Password $($UserAccount.Password)
		}         
    }
    catch {
        Write-Error $_
    }
}

Register-SitecoreInstallExtension -Command Invoke-EnsureLocalUserTask -As EnsureLocalUser -Type Task -Force

function NewLocalUser
{
	  PARAM
	  (
		[String]$UserName=$(throw 'Parameter -UserName is missing!'),
		[String]$Password=$(throw 'Parameter -Password is missing!')
	  )
	  Trap
	  {
		Write-Host "Error: $($_.Exception.GetType().FullName)" -ForegroundColor Red ; 
		Write-Host $_.Exception.Message; 
		Write-Host $_.Exception.StackTrack;
		break;
	  }
  
	  Write-Host "Creating $($UserName)";
  
	  #$response = Invoke-Expression -Command "NET USER $($UserName) `"/add`" $($Password) `"/passwordchg:no`" `"/expires:never`"";
  
	  $objOu = [ADSI]"WinNT://$env:COMPUTERNAME";
	  $objUser = $objOU.Create("User", $UserName);

	  $objUser.setpassword($Password);
	  $objUser.SetInfo();

	  $objUser.description = "$UserName";
	  $objUser.SetInfo();
  
	  $objUser.UserFlags.value = $objUser.UserFlags.value -bor 64;
	  $objUser.UserFlags.value = $objUser.UserFlags.value -bor 65536;
	  $objUser.SetInfo();  
  
	  Write-Host "Response from creating local user: $response";
}
