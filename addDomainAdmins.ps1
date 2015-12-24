########################################################################################################
# Script  : addDomainAdmins.ps1
# Usage   : Call after joining a member server to the domain
#
# Inputs  : Topology         - Forest topology
#			(see common.yml)
########################################################################################################

# Parameters
[CmdletBinding()]
Param(
	[Parameter(Mandatory)]
	[psobject]$Topology=$null
)

#----------------------------------------------------------------------------------------------
# Check if an object already exists in Active Directory
# You can use: CN=groupname,DC=....   or OU=ouname,DC=... 
Function ADObjectExists
{
	[CmdletBinding()]
	param(
		[string]$path
	)

	if ([ADSI]::Exists("LDAP://$path"))
	{
		return $true
	}
	
	return $false
}

#----------------------------------------------------------------------------------------------
# Check if user is in group
function IsMember([string]$searchName)
{
    $group = [ADSI]("WinNT://./Administrators,Group") 
	$members = @($group.psbase.invoke("Members"))
	$memberList = @()
	
	try
	{
		foreach ($m in $members) {
			$memberList += $m.GetType().InvokeMember("AdsPath", 'GetProperty', $null, $m, $null)
		}
	}
	catch
	{
		Throw "Error enumerating local Administrators group  because $($_.Exception.Message)"
	}
	
	$searchName = "WinNT://" + $searchName
	return ($memberList -Contains $searchName)
}

#----------------------------------------------------------------------------------------------
# Add forest domain admins to local member server Administrators group
function AddDomainAdmins
{
	$groupName = $Topology.forest.netbiosname + "/Domain Admins"

	if (-Not( IsMember $groupName ))
	{
		try
		{
			([ADSI]"WinNT://./Administrators,group").Add("WinNT://$groupName,Group")
		}
		catch
		{
			Throw "Error adding $groupName to local administators because $($_.Exception.Message)"
		}
	}
	else
	{
		Write-Verbose "$groupName already a member of local administrators"
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
if (-Not ($Topology)) { Throw "Error: missing Topology hash table!" }
if (-Not ($Topology.forest.netbiosname)) { Throw "Error: missing netbiosname in forest.domain dictionary!" }

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Throw "Must run powerShell as Administrator to perform these actions"     
}

# Add domain admins
AddDomainAdmins
