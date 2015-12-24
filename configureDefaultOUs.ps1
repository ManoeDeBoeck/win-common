########################################################################################################
# Script  : configureSiteOUs.ps1
#
# Purpose : Configure default OUs for the root/child domain
# Author  : Ard-Jan Barnas
# Date    : 4/29/2015
# Inputs  : Sites				- list of known sites and configuration
#		  : DomainOrgUnits		- list of default OrganizationalUnits
#			(see common.yml)
#
########################################################################################################

# Parameters
[CmdletBinding()]
Param(
	[Parameter(Mandatory)]
	[psobject]$Sites=$null,

	[Parameter(Mandatory)]
	[psobject]$DomainOrgUnits=$null
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
# Configure the OUs
Function Configure-OrganizationalUnits
{
	foreach ($defObj in $DomainOrgUnits.Keys)
	{
		# Check if the OU exists. If not then create it
		if (-Not ($DomainOrgUnits[$defObj].path)) 
		{
			$parentOU = $objRootDSE
		} 
		else 
		{
			$parentOU = $DomainOrgUnits[$defObj].path + "," + $objRootDSE
		}
		
		$strObj = "OU=" + $DomainOrgUnits[$defObj].name + "," + $parentOU
		if (-Not (ADObjectExists $strObj))
		{
			New-ADOrganizationalUnit -Name $DomainOrgUnits[$defObj].name -Path $parentOU
		}
		
		
		# Check if there are child OUs in the dictionary and create them
		if ($DomainOrgUnits[$defObj].subous)
		{
			$subOUs = $DomainOrgUnits[$defObj].subous
			$parentSubOU = "OU=" + $DomainOrgUnits[$defObj].name + "," + $parentOU
			
			foreach ($subou in $subOUs)
			{
				$strObj = "OU=" + $subou + "," + $parentSubOU
				if (-Not (ADObjectExists $strObj))
				{
					New-ADOrganizationalUnit -Name $subou -Path $parentSubOU
				}
			}
		}
		
		# Check if there are security groups specified in the dictionary and create them
		if ($DomainOrgUnits[$defObj].groups)
		{
			$groups = $DomainOrgUnits[$defObj].groups
			$parentOU = "OU=" + $DomainOrgUnits[$defObj].name + "," + $parentOU
			
			foreach ($group in $groups)
			{
				$strObj = "CN=" + $group + "," + $parentOU
				if (-Not (ADObjectExists $strObj))
				{
					New-ADGroup -Name $group -SamAccountName $group -GroupCategory Security -GroupScope Global -Path $parentOU	
				}
			}
		}

		# Check if there are security groups that need to be added to Domain Admins
		if ($DomainOrgUnits[$defObj].domainadmins)
		{
			$domainadmins = $DomainOrgUnits[$defObj].domainadmins
			foreach ($group in $domainadmins)
			{
				Add-ADGroupMember "Domain Admins" $group
			}
		}	
	}


	# Create site specific OUs
	foreach ($site in $Sites.Keys)
	{	
		# Create site specific OUs - borrow the sitename anc create subOUs for each site under Managed Servers
		$path = "OU=" + $DomainOrgUnits.ManagedServers.name + "," + $DomainOrgUnits.ManagedServers.path + "," + $objRootDSE
		$strObj = "OU=" + $site + "," + $path
		
		if (-Not (ADObjectExists $strObj))
		{
			try { New-ADOrganizationalUnit -Name $site -Path $path }
			catch
			{
				Throw "Error creating OU $site because $($_.Exception.Message)"
			}		
		}
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

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Throw "Must run powerShell as Administrator to perform these actions"     
}

#  RootDSE
$objRootDSE = (Get-ADRootDSE).defaultnamingcontext

# Configure OUs
Configure-OrganizationalUnits
