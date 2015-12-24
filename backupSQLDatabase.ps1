#------------------------------------------------------------------------------------------------------------
# Script  : /roles/win-sqlserver/backupSQLDatabase.ps1
# Purpose : Create a new database and join it to an availability group
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
# Backup database
function backupSQLDatabase
{
	$instance = $env:COMPUTERNAME
	if (-Not($SQLServer.config.instancename -eq "MSSQLSERVER")) {
		$instance += "\" + $SQLServer.config.instancename
	}
	
	try
	{
		# load SMO assembly
		[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") | Out-Null
		[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoExtended") | Out-Null
		[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null
		[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum") | Out-Null

		# Setup the SMO connection to the SQL instance
		$server = New-Object Microsoft.SqlServer.Management.Smo.Server("$instance")
		$server.ConnectionContext.LoginSecure = $false
		$server.ConnectionContext.set_Login("sa")
		$server.ConnectionContext.set_Password($SQLServer.config.sapwd)
	
		# Check if the database already exists
		if (-Not($server.Databases.Contains($DatabaseName)))
		{
			Throw "Error backing up database $DatabaseName. $DatabaseName doesn't exist!"
		}
		else
		{
			$timestamp = Get-Date -format yyyy-MM-dd-HH-mm-ss
			$backupTarget = "\\" + $SQLServer.servicehost.hostname + "\" + $SQLServer.servicehost.backupsharename
			
			$database = $server.Databases[$DatabaseName]
			
			$backup = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Backup
			$backup.Action = "Database"
			$backup.BackupSetName = "$database.Name Backup"
			$backup.Database = $database.Name
			$backup.Incremental = 0
			$backup.Devices.AddDevice($backupTarget + "\" + $database.Name + "_full_" + $timestamp + ".bak", "File")
			$backup.SqlBackup($server)
		}
	}
	catch
	{
		$linenr = $_.InvocationInfo.ScriptLineNumber
		$line = $_.InvocationInfo.Line
		Throw "Error backing up database $DatabaseName at line $linenr - $line. $($_.Exception.Message)"
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
if (-Not ($SQLServer.servicehost)) { Throw "Error: missing servicehost parameter in SQLServer dictionary!" }
if (-Not ($SQLServer.servicehost.backupsharename)) { Throw "Error: missing servicehost.backupsharename parameter in SQLServer dictionary!" }
if (-Not ($SQLServer.config.sapwd)) { Throw "Error: missing sapwd parameter in SQLServer dictionary!" }
if (-Not ($SQLServer.config.instancename)) { Throw "Error: missing InstanceName parameter in SQLServer dictionary!" }

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
backupSQLDatabase



	
