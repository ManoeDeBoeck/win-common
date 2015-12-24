########################################################################################################
# Script  : removeComputerAccount.ps1
# Purpose : Removed a computer account from the forest or domain
#
# Inputs  : Topology		- Specifies forest credentials
#           ComputerName    - Computer account to remove
#			(see common.yml)
########################################################################################################

# Parameters
[CmdletBinding()]
Param(
	[Parameter(Mandatory)]
	[psobject]$Topology=$null,

	[Parameter(Mandatory)]
	[string]$ComputerName=$null
)

#----------------------------------------------------------------------------------------------
# Join server to the domain
function removeComputerAccount
{
	$Name = $ComputerName + "$"
	$Credential = GetEnterpriseCredential
	
	try
	{
		$Computer = Get-ADcomputer -Filter {SAMAccountName -eq $Name}
		if ($Computer)
		{
			try
			{
				Remove-ADObject `
				-Credential $Credential `
				-Identity $Computer.distinguishedname `
				-Recursive `
				-Confirm:$false
			}
			catch
			{
				Throw "Error removing computer account because $($_.Exception.Message)"
			}
		}
	}
	catch
	{
		# Computer account not found. Ignore.
	}
}

#----------------------------------------------------------------------------------------------

function GetEnterpriseCredential
{
	# Build the credentials object
	$forestUserName = $Topology.forest.netbiosname + "\Administrator"
	$forestPassword = ConvertTo-SecureString $Topology.forest.password -AsPlaintext -Force
	$EnterpriseCredential = New-Object -typename System.Management.Automation.PSCredential `
	-argumentlist $forestUserName, $forestPassword
	
	return $EnterpriseCredential
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

# Make sure we have all the parameters that we need
if (-Not ($ComputerName)) { Throw "Error: missing ComputerName parameter!" }
if (-Not ($Topology.forest.password)) { Throw "Error: missing Password parameter in Topology!" }

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Throw "Must run powerShell as Administrator to perform these actions"     
}

# Remove the computer account	
removeComputerAccount

