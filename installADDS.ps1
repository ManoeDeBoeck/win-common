# ------------------------------------------------------------------------------------------------------------------
# Script  : installADDS.ps1
# Purpose : Installs the ADDS role and features
# Inputs  : 
# ------------------------------------------------------------------------------------------------------------------

# Install ADDS features
Function InstallADDS
{
	try
	{
		# start the install process
		Start-Job -Name addFeature -ScriptBlock {
			Write-Host "Installing ADDS and GPMC"
			Add-WindowsFeature -Name "ad-domain-services" -IncludeAllSubFeature -IncludeManagementTools
			Add-WindowsFeature -Name "gpmc" -IncludeAllSubFeature -IncludeManagementTools 
		}
		
		# Wait for the features to be installed
		Write-Host "Waiting for feature installation to complete"
		Wait-Job -Name addFeature
	}
	catch
	{
		Throw "Failed to install required Windows features because $($_.Exception.Message)"
	}
}

#----------------------------------------------------------------------------------------------
# Setup error handling
$VerbosePreference = "Continue"

# Setup error handling.
Trap
{
    Write-Error $_
    Exit 1
}
$ErrorActionPreference = "Stop"

#----------------------------------------------------------------------------------------------
# MAIN
#----------------------------------------------------------------------------------------------

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Write-Warning "Must run powerShell as Administrator to perform these actions"     
	exit 1
}

# Install the ADDS role and features
InstallADDS


