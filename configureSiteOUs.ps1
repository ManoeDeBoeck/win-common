########################################################################################################
# Script  : configureSiteOUs.ps1
# Usage   : Call prior to adding a member server to the domain so we can be sure the target OU for
#           the member server exists.
#
# Author  : Ard-Jan Barnas
# Date    : 4/29/2015
# Inputs  : SiteName 		 - Name of the site OU to create to store member servers
#		  : DomainOUs	 - list of default OrganizationalUnits
#			(see common.yml)
#
# Notes   * Even though not required, this script will check all default OUs every time it is run
#
########################################################################################################

# Parameters
[CmdletBinding()]
Param(
	[Parameter(Mandatory)]
	[string]$SiteName=$null,

	[Parameter(Mandatory)]
	[psobject]$DomainOUs=$null
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

	Write-Verbose "Checking if $path exists..."
	if ([ADSI]::Exists("LDAP://$path"))
	{
		return $true
	}
	
	return $false
}

#----------------------------------------------------------------------------------------------
# Configure the OUs
Function ConfigureOrganizationalUnits
{
	# Get RootDSE
	$objRootDSE = (Get-ADRootDSE).defaultnamingcontext

	foreach ($obj in $DomainOUs.Keys)
	{
		# Check if the OU exists. If not then create it
		if (-Not ($DomainOUs[$obj].path)) {
			$parentOU = $objRootDSE
		} else {
			$parentOU = $DomainOUs[$obj].path + "," + $objRootDSE
		}
		
		Write-Verbose "Setting parentOU to $parentOU"
		
		#check that the parentOU exists
		if (-Not(ADObjectExists $parentOU))
		{
			$OUParts = $parentOU.Split(",")
			$childOU = $OUParts[0]
			$name = $childOU.Replace("OU=","")
			$path = $parentOU.Replace("$childOU,","")

			Write-Verbose "Parent OU $parentOU does not exist... attempting to create, using name $name and path $path"
			New-ADOrganizationalUnit -Name $name -Path $path
		}
		
		$name = $DomainOUs[$obj].name
		$strObj = "OU=" + $name + "," + $parentOU
		if (-Not (ADObjectExists $strObj)) 
		{
			Write-Verbose "Creating OU $name in $parentOU"
			New-ADOrganizationalUnit -Name $name -Path $parentOU
		}
		
		
		# Check if there are child OUs in the dictionary and create them
		if ($DomainOUs[$obj].subous)
		{
			$parentSubOU = "OU=" + $DomainOUs[$obj].name + "," + $parentOU
			foreach ($subou in $DomainOUs[$obj].subous)
			{
				$strObj = "OU=" + $subou + "," + $parentSubOU
				if (-Not (ADObjectExists $strObj)) 
				{
					Write-Verbose "Creating OU $subou in $parentSubOU"
					New-ADOrganizationalUnit -Name $subou -Path $parentSubOU
				}
			}
		}
		
		# Check if there are security groups specified in the dictionary and create them
		if ($DomainOUs[$obj].groups)
		{
			$parentOU = "OU=" + $DomainOUs[$obj].name + "," + $parentOU
			foreach ($group in $groups = $DomainOUs[$obj].groups)
			{
				try
				{
					$g = Get-ADGroup $group
				}
				catch
				{
					Write-Verbose "Creating group $group"
					New-ADGroup -Name $group -SamAccountName $group -GroupCategory Security -GroupScope Global -Path $parentOU	
				}
			}
		}

		# Check if there are security groups that need to be added to Domain Admins
		if ($DomainOUs[$obj].domainadmins)
		{
			foreach ($group in $DomainOUs[$obj].domainadmins) 
			{
				Write-Verbose "Adding $group to Domain Admins"
				Add-ADGroupMember "Domain Admins" $group
			}
		}	
	}


	# Create site specific OU
	$path = "OU=" + $DomainOUs.managedservers.name + "," + $DomainOUs.managedservers.path + "," + $objRootDSE
	$strObj = "OU=" + $SiteName + "," + $path
	
	if (-Not (ADObjectExists $strObj))
	{
		try 
		{ 
			Write-Verbose "Creating OU $sitename in $path"
			New-ADOrganizationalUnit -Name $SiteName -Path $path 
		}
		catch
		{
			Throw "Error creating OU $SiteName because $($_.Exception.Message)"
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

# Make sure we have all the parameters that we need
if (-Not ($SiteName)) { Throw "Error: missing sitename parameter in DomainConfig!" }
if (-Not ($DomainOUs.ManagedServers.name)) { Throw "Error: missing DomainOUs.ManagedServers.name hashtable parameter!" }
if (-Not ($DomainOUs.ManagedServers.path)) { Throw "Error: missing DomainOUs.ManagedServers.path hashtable parameter!" }

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Throw "Must run powerShell as Administrator to perform these actions"     
}


# Configure OUs
ConfigureOrganizationalUnits
