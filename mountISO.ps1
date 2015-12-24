########################################################################################################
# Script  : mountISO.ps1
# Usage   : Mounts an ISO
########################################################################################################

# Parameters
[CmdletBinding()]
Param(
	[Parameter(Mandatory=$false)]
	[string]$FileName=$null
)

#----------------------------------------------------------------------------------------------
# Create user account
function mountISO
{
	try
	{
		$mountResult = Mount-DiskImage -ImagePath $FileName -Confirm
		$driveLetter = ($mountResult | Get-Volume).DriveLetter
		
		Write-Host $driveLetter
	}
	catch
	{
		Throw "Error: unable to mount ISO $FileName"
	}
}

#----------------------------------------------------------------------------------------------
# Setup error handling.
$VerbosePreference = "Continue"

Trap
{
    Write-Error $_
    Exit 1
}
$ErrorActionPreference = "Stop"

#----------------------------------------------------------------------------------------------
# Main
#----------------------------------------------------------------------------------------------

# Make sure we have all the parameters that we need
if (-Not ($FileName)) { Throw "Error: missing ISO filename!" }

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Throw "Must run powerShell as Administrator to perform these actions"     
}

# Create User
mountISO

