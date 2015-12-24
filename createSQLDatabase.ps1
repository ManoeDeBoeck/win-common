#------------------------------------------------------------------------------------------------------------
# Script  : /roles/win-sqlserver/createSQLDatabase.ps1
# Purpose : Create a new database
#
# Inputs  : 
#-------------------------------------------------------------------------------------------------------------

# Parameters
[CmdletBinding()]
Param(
	[Parameter(Mandatory)]
	[psobject]$SQLServer=$null,
	
	[Parameter(Mandatory)]
	[string]$DatabaseName=$null
)

#----------------------------------------------------------------------------------------------
# Create database
function createDatabase
{
	$instance = $env:COMPUTERNAME
	if (-Not($SQLServer.config.instancename -eq "MSSQLSERVER")) {
		$isntance += "\" + $SQLServer.config.instancename
	}
	
	try
	{
		# load SMO assembly
		[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') 

		# Setup the SMO connection to the SQL instance
		$server = New-Object Microsoft.SqlServer.Management.Smo.Server("$instance")
		$server.ConnectionContext.LoginSecure = $false
		$server.ConnectionContext.set_Login("sa")
		$server.ConnectionContext.set_Password($SQLServer.config.sapwd)
	
		# Check if the database already exists
		if (-Not($server.Databases.Contains($DatabaseName)))
		{
			$database = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $DatabaseName
			$database.RecoveryModel = 'Full'
			$database.Create()
		}
		else
		{
			Write-Verbose "Skipping database creation of $DatabaseName. $DatabaseName already exists."
		}
		
		$database
	}
	catch
	{
		$linenr = $_.InvocationInfo.ScriptLineNumber
		$line = $_.InvocationInfo.Line
		Throw "Error creating database $DatabaseName on $instance at line $linenr - $line. $($_.Exception.Message)"
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
if (-Not ($DatabaseName)) { Throw "Error: missing DatabaseName parameter!" }
if (-Not ($SQLServer.config.sapwd)) { Throw "Error: missing sapwd parameter in Cluster dictionary!" }
if (-Not ($SQLServer.config.instancename)) { Throw "Error: missing InstanceName parameter in Cluster dictionary!" }

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Throw "Must run powerShell as Administrator to perform these actions"     
}

# Import SQL powershell module
Import-Module "sqlps" -DisableNameChecking

# Run main functions
createDatabase



	
