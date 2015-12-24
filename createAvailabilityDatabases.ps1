#------------------------------------------------------------------------------------------------------------
# Script  : /files/createAvailabilityDatabases.ps1
# Purpose : Create one or more availability group databases
#
# Inputs  : 
#-------------------------------------------------------------------------------------------------------------

# Parameters
[CmdletBinding()]
Param
(
    [Parameter(Mandatory)]
    [psobject]$Cluster,

    [Parameter(Mandatory)]
    [psobject]$SQLServer,

    [Parameter(Mandatory)]
    [psobject]$Domain
)

#----------------------------------------------------------------------------------------------
# Retrieve server netbiosname from fqdn
function GetServerName([string]$fqdn, $server)
{
	foreach ($name in $Cluster.clusternodes) 
	{
		if ($server.NetName -Contains $name) 
		{ 
			return $name	
		}
	}
}

#----------------------------------------------------------------------------------------------
# Set up a connection to each server object
function GetServerConnection($serverName)
{
	# Check if we have a default or custom instance
	if (-Not($SQLServer.config.instancename -eq "MSSQLSERVER")) {
		$serverName += "\" + $SQLServer.config.instancename
	}

	try
	{
		# Connection to the server instance, using SQL authentication
		Write-Verbose "Creating SMO Server object for server: $serverName"
		$server = New-Object Microsoft.SQLServer.Management.SMO.Server($serverName) 
		$server.ConnectionContext.LoginSecure = $false
		$server.ConnectionContext.set_Login("sa")
		$server.ConnectionContext.set_Password($SQLServer.config.sapwd)
		return $server
	}
	catch
	{
		$linenr = $_.InvocationInfo.ScriptLineNumber
		$line = $_.InvocationInfo.Line
		Throw "Error creating server object for $serverName - line $linenr - $line. $($_.Exception.Message)"
	}
}

#----------------------------------------------------------------------------------------------
# Create database
function createSQLDatabase($server, $db)
{
	try
	{
		# Check if the database already exists
		if (-Not($server.Databases.Contains($db)))
		{
			Write-Verbose "Creating database $db on $server.NetName"
			$database = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $db
			$database.RecoveryModel = 'Full'
			$database.Create()
		}
		else
		{
			Write-Verbose "Skipping database creation of $db. $db already exists."
		}
	}
	catch
	{
		$error[0]|format-list -force
		$linenr = $_.InvocationInfo.ScriptLineNumber
		$line = $_.InvocationInfo.Line
		Throw "Error creating database $DatabaseName on $instance at line $linenr - $line. $($_.Exception.Message)"
	}
}

#----------------------------------------------------------------------------------------------
# Restore database
function restoreSQLDatabase($server, $db)
{
	$backupTarget = Join-Path "\\" $SQLServer.servicehost.hostname
	$backupTarget = Join-Path $backupTarget $SQLServer.servicehost.backupsharename

	try
	{
		$backupFile = Join-Path $backupTarget $db

		# Restore the database backup
		Write-Verbose "Starting restore of $backupFile to server $server.NetName"
		
		$restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
		$restore.Database = $db
		$restore.Action = [Microsoft.SqlServer.Management.Smo.RestoreActionType]::Database
		$restore.Devices.AddDevice("$backupFile_full.bak", [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
		$restore.NoRecovery = $true
		$restore.SqlRestore($server)

		# Restore the transcaction log
		Write-Verbose "Starting transaction log restore of $backupFile"
		
		$restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
		$restore.Database = $db
		$restore.Action = [Microsoft.SqlServer.Management.Smo.RestoreActionType]::Log
		$restore.Devices.AddDevice("$backupFile_log.trn", [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
		$restore.NoRecovery = $true
		$restore.SqlRestore($server)
	}
	catch
	{
		$error[0]|format-list -force
		$linenr = $_.InvocationInfo.ScriptLineNumber
		$line = $_.InvocationInfo.Line
		Throw "Error restoring database $DatabaseName at line $linenr - $line. $($_.Exception.Message)"
	}
}

#----------------------------------------------------------------------------------------------
# Backup database
function backupSQLDatabase($server, $db)
{
	$backupTarget = Join-Path "\\" $SQLServer.servicehost.hostname
	$backupTarget = Join-Path $backupTarget $SQLServer.servicehost.backupsharename

	try
	{
		$backupFile = Join-Path $backupTarget $db
		
		# Make a full backup of the database
		Write-Verbose "Starting backup of $db to $backupTarget"

		$backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
		$backup.Database = $db
		$backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Database
		$backup.Initialize = $True
		$backup.Devices.AddDevice("$backupFile_full.bak", [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
		$backup.SqlBackup($server) | Out-Null
		
		# Make a log backup of the database
		Write-Verbose "Starting backup of transaction log for $db to $backupTarget"

		$backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
		$backup.Database = $db
		$backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Log
		$backup.Initialize = $True
		$backup.Devices.AddDevice("$backupFile_log.trn", [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
		$backup.SqlBackup($server) | Out-Null
	}
	catch
	{
		$error[0]|format-list -force
		$linenr = $_.InvocationInfo.ScriptLineNumber
		$line = $_.InvocationInfo.Line
		Throw "Error backing up $backupFile - line $linenr - $line. $($_.Exception.Message)"
	}
}

#----------------------------------------------------------------------------------------------
# Add databases to availability group
function AddAvailabilityDatabase($agName, $databaseList)
{
	$serverObjects = @()
	foreach ($serverName in $Cluster.clusternodes)
	{
		Write-Verbose "Creating server connection object for $serverName"
		$serverObjects += GetServerConnection($serverName)
	}

	# assign primary and secondary endpoint servers
	$primaryServer, $secondaryServers = $serverObjects

	# See if the availability group already exists
	$ag = $primaryServer.AvailabilityGroups | Where-Object {$_.Name -eq $agName}
	if (-Not($ag))
	{
		# If the availability group doesn't exist, error out.
		Throw "Error: availability group $agName doesn't exist!"
	}

	# Traverse the list of databases and add them to the availability group
	foreach ($db in $databaseList)
	{
		try
		{
			$dbCheck = $primaryServer.Databases | Where-Object {$_.Name -eq $db}
			if (-Not($dbCheck))
			{
				# create the database(s) on the primary replica
				Write-Verbose "Creating database $db on primary replica"
				createSQLDatabase $primaryServer $db
			}
			else
			{
				# Database already exists
				Write-Verbose "Database $db already exists on primary replica. Skipping"
			}
			
			# Make sure the recovery model is set to full
			if ($primaryServer.Databases[$db].RecoveryModel -ne "Full")
			{
				Write-Verbose "Setting recovery model to Full for $db"
				$primaryServer.Databases[$db].RecoveryModel = "Full"
				$primaryServer.Databases[$db].alter()
			}

			# See if the database is already in an availability group
			if (-Not($dbCheck.AvailabilityGroupName))
			{
				# backup the database(s) on the primary replica
				backupSQLDatabase $primaryServer $db

				# Create the availability database and add it to the availability group
				Write-Verbose "Creating availability database $db in $agName"
				
				$agDb = New-Object -TypeName Microsoft.SQLServer.Management.Smo.AvailabilityDatabase -ArgumentList $ag,$db
				$ag.AvailabilityDatabases.add($agDb);
				$agDb.create()
				$ag.alter()
			}
			else
			{
				# Database already in availability group 
				Write-Verbose "Database $db already part of availability group $agName. Skipping"
			}
		}
		catch
		{
			$error[0]|format-list -force
			$linenr = $_.InvocationInfo.ScriptLineNumber
			$line = $_.InvocationInfo.Line
			Throw "Failed to add $db on $agName - line $linenr - $line. $($_.Exception.Message)"
		}
	}
	
	
	# Handle the database for each secondary replica
	foreach ($secondary in $secondaryServers) 
	{
		# create the availability group database object
		foreach ($db in $databaseList)
		{
			try
			{
				# See if the database is already present on the secondary replica
				$dbCheck = $secondary.Databases | Where-Object {$_.Name -eq $db}
				if (-Not($dbCheck))
				{
					# restore the database on the secondary replica
					Write-Verbose "Restoring database $db on secondary replica $secondary.NetName"
					restoreSQLDatabase $secondary $db
				
					# Wait for restore to be completed
					while($true)
					{
						Write-Verbose "Waiting for availability database $db to be restored and available"
						Start-Sleep -Seconds 15

						$ag = $secondary.AvailabilityGroups | Where-Object {$_.Name -eq $agName}
						$agDb = $ag.AvailabilityDatabases | Where-Object {$_.Name -eq $db}
						$ag = $secondary.AvailabilityGroups | Where-Object {$_.Name -eq $agName}
						$ag.AvailabilityDatabases.Refresh()
						$agDb=$ag.AvailabilityDatabases | Where-Object {$_.Name -eq $db}
						if ($agDb)
						{break}
					}
				}
				else
				{
					# Database found on secondary replica
					Write-Verbose "Database already exist on secondary replica $secondary.NetName. Skipping"
				}
				
				# Join database to availability group
				if (-Not($dbCheck.AvailabilityGroupName))
				{
					Write-Verbose "Joining $db to $agName"
					$secondary.AvailabilityGroups[$agName].AvailabilityDatabases[$db].JoinAvailablityGroup()
				}
				else
				{
					# Database on secondary replica already part of availability group
					Write-Verbose "Database $db on secondary replica $secondary.NetName already part of availability group. Skipping"
				}
			}
			catch
			{
				$error[0]|format-list -force
				$linenr = $_.InvocationInfo.ScriptLineNumber
				$line = $_.InvocationInfo.Line
				Throw "Failed to add $db on $agName - line $linenr - $line. $($_.Exception.Message)"
			}
		}
	}
}

#----------------------------------------------------------------------------------------------
# Create the availability group
function CreateAvailabilityGroup
{
	# create each availability group defined
	foreach ($agix in $Cluster.availabilitygroups.keys)
	{
		# Make sure we have the data we need
		if (-Not($Cluster.availabilitygroups[$agix].name)) { Throw "Error: missing availabilityGroup.name parameter in Cluster dictionary!" }

		# Set the availability group name
		$agName = $Cluster.availabilitygroups[$agix].name

		# If there are any databases specified add them to the availability group
		if ($Cluster.availabilitygroups[$agix].databases)
		{
			Write-Verbose "Adding databases for availability group $agName"
			AddAvailabilityDatabase $agName @($Cluster.availabilitygroups[$agix].databases)
		}
	}
}

#----------------------------------------------------------------------------------------------

function GetDomainCredential
{
	$userName = $Domain.netbiosname + "\Administrator"
	$password = ConvertTo-SecureString $Domain.password -AsPlaintext -Force
	$Credential = New-Object -typename System.Management.Automation.PSCredential -argumentlist $userName, $password
	Write-Host "Using user account $userName / $password"
	
	return $Credential
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
if (-Not ($Cluster.availabilitygroups)) { Throw "Error: missing availabilitygroups parameter in Cluster dictionary!" }
if (-Not ($Cluster.clusternodes)) { Throw "Error: missing clusternodes parameter in Cluster dictionary!" }
if (-Not ($SQLServer.config.sapwd)) { Throw "Error: missing sapwd parameter in Cluster dictionary!" }
if (-Not ($SQLServer.config.instancename)) { Throw "Error: missing InstanceName parameter in Cluster dictionary!" }

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Throw "Must run powerShell as Administrator to perform these actions"     
}

# load SMO assembly
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoExtended") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum") | Out-Null

# Create the availability group
CreateAvailabilityGroup