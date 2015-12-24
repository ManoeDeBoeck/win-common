########################################################################################################
# Script  : createDomainUser.ps1
# Usage   : creates a user account in Active Directory
#
# Inputs  : UserAccount dictionary
########################################################################################################

# Parameters
[CmdletBinding()]
Param(
	[Parameter(Mandatory)]
	[string]$Placement=$null,

	[Parameter(Mandatory)]
	[psobject]$UserAccount=$null,

	[Parameter(Mandatory)]
	[psobject]$Topology=$null

)

#----------------------------------------------------------------------------------------------
# Create user account
function createDomainUser
{
	# Get the domain credentials
	$credential = GetDomainCredential
	
	# Remove the domain name from the username
	$repstring = $Domain.netbiosname + "\"
	$username = $UserAccount.username.Replace($repstring, "")
	
	# Set the OU path
	$ouPath = "{0},{1}" -f $UserAccount.ouPath, $Domain.rootDse
	
	# See if the user already exists
	$user = Get-ADUser -f { SAMAccountName -eq $username }
	if (-Not($user))
	{
		Write-Verbose "Creating user $username in $ouPath"
		try
		{
			# Create a new user account
			New-ADUser `
			-Server $Domain.domainName `
			-Credential $credential `
			-SAMAccountName $userName `
			-Name $userName `
			-DisplayName $userName `
			-GivenName $userName `
			-AccountPassword (ConvertTo-SecureString -AsPlainText $UserAccount.password -Force) `
			-Enabled $true `
			-CannotChangePassword $true `
			-PasswordNeverExpires $true `
			-Path "$oupath"
		}
		catch
		{
			$linenr = $_.InvocationInfo.ScriptLineNumber
			$line = $_.InvocationInfo.Line
			Throw "Error creating user at line $linenr - $line. $($_.Exception.Message)"
		}
	}
}

#----------------------------------------------------------------------------------------------

function GetDomainCredential
{
	# Build the credentials object
	$domainUserName = $Domain.netbiosname + "\Administrator"
	$domainPassword = ConvertTo-SecureString $Domain.password -AsPlaintext -Force
	$DomainCredential = New-Object -typename System.Management.Automation.PSCredential -argumentlist $domainUserName, $domainPassword
	
	Write-Verbose "Using domain credential $domainUserName"
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
if (-Not ($UserAccount.oupath)) { Throw "Error: missing oupath parameter!" }
if (-Not ($Domain.domainname)) { Throw "Error: missing domainName parameter in Domain!" }
if (-Not ($Domain.password)) { Throw "Error: missing domainPassword parameter in Domain!" }
if (-Not ($Domain.rootDse)) { Throw "Error: missing rootDse parameter in Domain!" }

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Throw "Must run powerShell as Administrator to perform these actions"     
}

# Create User
createDomainUser
