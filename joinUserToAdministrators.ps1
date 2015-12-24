########################################################################################################
# Script  : joinUserToAdministrators.ps1
# Usage   : joins a given domain-based user account to the local administrators group
#
# Inputs  : UserAccount dictionary
########################################################################################################

# Parameters
[CmdletBinding()]
Param(
	[Parameter(Mandatory)]
	[psobject]$UserAccount=$null,

	[Parameter(Mandatory)]
	[string]$Placement=$null,

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
function IsMember([string]$userName)
{
	$group =[ADSI]"WinNT://$($env:COMPUTERNAME)/Administrators"
	$members = @($group.psbase.invoke("Members"))
	$memberList = @()

	try
	{
		foreach ($m in $members) {
			$member = $m.GetType().InvokeMember("AdsPath", 'GetProperty', $null, $m, $null)
			$memberList += $member
		}
		
		Write-Host "Found members:"
		Write-Host $memberList
	}
	catch
	{
		Throw "Error enumerating local Administrators group  because $($_.Exception.Message)"
	}

	Write-Host "Searching for $userName"
	return ($memberList -Contains $userName)
}

#----------------------------------------------------------------------------------------------
# Add user account to a local administrators group
function AddLocalAdminUser
{
	$group =[ADSI]"WinNT://$($env:COMPUTERNAME)/Administrators"
	$username = "WinNT://" + $Domain.netbiosname + "/" + $UserAccount.userName
	
	if (-Not (IsMember($userName) ))
	{
		try
		{
			Write-Verbose "Adding $userName to local administrators"
			([ADSI]"WinNT://./Administrators,group").Add("$username,User")
		}
		catch
		{
			Throw "Error adding $userName to local administrators because $($_.Exception.Message)"
		}
	}
	else
	{
		Write-Verbose "User $userName already a member of $group"
	}
}

#----------------------------------------------------------------------------------------------

function GetDomainCredential
{
	# Build the credentials object
	$domainUserName = $Domain.netbiosname + "\Administrator"
	$domainPassword = ConvertTo-SecureString $Domain.password -AsPlaintext -Force
	$DomainCredential = New-Object -typename System.Management.Automation.PSCredential -argumentlist $domainUserName, $domainPassword
	
	return $DomainCredential
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

# Set the domain dictionary to use
if ($Placement -eq "forest") {
	Write-Verbose "Active Directory placement set to Forest"
	$Domain = $Topology.forest
}
elseif ($Placement -eq "domain")
{
	Write-Verbose "Active Directory placement set to Domain"
	$Domain = $Topology.domain
}
else
{
	Throw "Error: Placement misconfigured. Needs to specify domain or forest. Current value: $Placement"
}

# Make sure we have all the parameters that we need
if (-Not ($UserAccount.username)) { Throw "Error: missing username!" }
if (-Not ($UserAccount.password)) { Throw "Error: missing password!" }
if (-Not ($Domain.domainname)) { Throw "Error: missing domainName parameter in Domain!" }
if (-Not ($Domain.password)) { Throw "Error: missing domainPassword parameter in Domain!" }

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Throw "Must run powerShell as Administrator to perform these actions"     
}

# Add to group
AddLocalAdminUser
