#-----------------------------------------------------------------------------------------------------
# Script  : createDomain.ps1
# Purpose : Configure the first domain controller in the root forest
#
# Inputs  : Topology - Specifies domainName, administrator password, domain mode
#			(see common.yml)
#-----------------------------------------------------------------------------------------------------

# Parameters
[CmdletBinding()]
Param(
	[Parameter(Mandatory)]
	[psobject]$Topology=$null,
	
	[Parameter(Mandatory)]
	[psobject]$Site=$null,

	[Parameter(Mandatory)]
	[string]$Placement=$null
)

#----------------------------------------------------------------------------------------------
# Create a new Forest
Function CreateForest
{
	# Check if the server is already promoted to a domain controller
	try
	{
		Write-Host "Checking if server is promoted"
		(Get-ADForest).ForestMode
	}
	catch
	{
		Write-Host "Creating forest"
		
		# Set the password
		$pwd = ConvertTo-SecureString $Domain.password -AsPlaintext -Force
		
		# Create Forest 
		try
		{
			Import-Module ADDSDeployment
			Install-ADDSForest -CreateDnsDelegation:$false `
			-DatabasePath "C:\Windows\NTDS" `
			-ForestMode $Domain.forestmode `
			-DomainMode $Domain.domainmode `
			-DomainName $Domain.domainname `
			-DomainNetbiosName $Domain.netbiosname `
			-InstallDns:$true `
			-SafeModeAdministratorPassword $pwd `
			-LogPath "C:\Windows\NTDS" `
			-NoRebootOnCompletion:$true `
			-SysvolPath "C:\Windows\SYSVOL" `
			-Force:$true
		}
		catch
		{
			Throw "Failed to create forest because $($_.Exception.Message)"
		}		
	}
}

#----------------------------------------------------------------------------------------------
# Install and configure ADDS
function CreateChildDomain
{
	try
	{
		# Let's see if the server is already promoted
		Write-Host "Checking if server is promoted"
		(Get-ADForest).DomainMode
	}
	catch
	{
		# Server is not promoted. Let's do it...
		Write-Verbose "Creating child domain"
		
		# Build the credentials object
		$Credential = GetEnterpriseCredential

		# Set the domain administrator password
		$domainPassword = ConvertTo-SecureString $Domain.password -AsPlaintext -Force
		
		# Now let's create the child domain
		try
		{
			Import-Module ADDSDeployment
			Install-ADDSDomain -CreateDnsDelegation `
			-Credential $Credential `
			-DomainType childdomain `
			-DomainMode $Domain.domainMode `
			-SiteName $Site.sitename `
			-DatabasePath 'C:\Windows\NTDS' `
			-ParentDomainName $Topology.forest.domainname `
			-NewDomainName $Domain.netbiosname.ToLower() `
			-InstallDns:$true `
			-LogPath 'C:\Windows\NTDS' `
			-NoGlobalCatalog:$false `
			-SafeModeAdministratorPassword $domainPassword `
			-SysvolPath 'C:\Windows\SYSVOL' `
			-NoRebootOnCompletion:$true `
			-Force:$true
		}
		catch
		{
			Throw "Failed to add domain controller because $($_.Exception.Message)"
		}		
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

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Throw "Must run powerShell as Administrator to perform these actions"     
}

# Set the domain dictionary to use
$Forest = $Placement -eq "forest"
if ($Forest) {
	$Domain = $Topology.forest
}
else
{
	$Domain = $Topology.domain

	# If there is a domain specified in the SiteConfig dictionary, 
	# use that instead of the Topology.domain
	if ($Site.domain) {
		$Domain = $Site.domain
	}
}

# Check that we have all the necessary domain parameters
if (-Not ($Site.sitename)) { Throw "Error: missing SiteName parameter in SiteConfig!" }
if (-Not ($Domain.netBiosName)) { Throw "Error: missing NetBiosName parameter in Topology!" }
if (-Not ($Domain.password)) { Throw "Error: missing Password parameter in Topology!" }
if (-Not ($Domain.domainMode)) { Throw "Error: missing domainMode parameter in Topology!" }
if (-Not ($Topology.forest.domainname)) { Throw "Error: missing DomainName parameter in Forest Topology!" }
if (-Not ($Topology.forest.netbiosname)) { Throw "Error: missing NetBiosName parameter in Forest Topology!" }
if (-Not ($Topology.forest.password)) { Throw "Error: missing Password parameter in Forest Topology!" }
if (-Not ($Topology.forest.forestMode)) { Throw "Error: missing forestMode parameter in Forest Topology!" }
if (-Not ($Topology.forest.domainMode)) { Throw "Error: missing domainMode parameter in Forest Topology!" }

if ($Forest) 
{
	# Create a new forest
	CreateForest
}
else
{
	# Create a new child domain
	CreateChildDomain
}
