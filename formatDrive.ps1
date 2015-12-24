########################################################################################################
# Script  : formatDrive.ps1
# Usage   : Brings a drive online and formats it (used for SCDP and SQL D: drive)
########################################################################################################

# Parameters
[CmdletBinding()]
Param(
	[Parameter(Mandatory)]
	[string]$Drive=$null,

	[Parameter(Mandatory=$false)]
	[string]$DriveSize=$null
)

#----------------------------------------------------------------------------------------------
# Create user account
function formatDrive
{
	# Setting the drive letter
	$driveLetter = $drive[0]
	
	# Make sure we're not formatting the C: drive
	$checkDriveLetter = [string]::Compare($driveLetter,"C", $False)
	if ($checkDriveLetter -eq 0)
	{
		Throw "WARNING! Cannot format drive C:  Incorrect target drive letter selected!"
	}
	
	try
	{
		$disk = Get-Disk | Where PartitionStyle -eq 'RAW'
		if ($disk)
		{
			foreach ($d in $disk)
			{
				# make sure we're not targetting the config drive (64MB)
				if ($disk.Size -ge 68000000)
				{
					# initialize the disk and bring online
					Write-Verbose "Initializing disk"
					Initialize-Disk -Number $d.Number -PartitionStyle MBR
					
					# create partition
					Write-Verbose "Creating partition"
					New-Partition -DiskNumber $d.Number -DriveLetter "$DriveLetter" -UseMaximumSize
					
					# format
					Write-Verbose "Formatting..."
					Format-Volume -DriveLetter "$DriveLetter" -FileSystem NTFS -Confirm:$false
				}
			}
		}
		else
		{
			# No RAW partition found. Check for unformatted drives
			$disk = Get-Disk | Where Size -gt 100GB
			if ($disk)
			{
				foreach ($d in $disk)
				{
                    $ErrorActionPreference = "SilentlyContinue"
					$p = Get-Partition -DiskNumber $d.Number
                    $ErrorActionPreference = "Stop"

					if (-Not($p))
					{
						$diskNumber = $d.Number
						
						# create partition
						Write-Verbose "Creating partition on disk $diskNumber, drive letter $driveLetter..."
						New-Partition -DiskNumber $d.Number -DriveLetter "$DriveLetter" -UseMaximumSize
						
						# format
						Write-Verbose "Formatting partition on disk $diskNumber, drive letter $driveLetter..."
						Format-Volume -DriveLetter "$DriveLetter" -FileSystem NTFS -Confirm:$false
					}
				}
			}
		}
	}
	catch
	{
		Throw "Error: unable to format drive $Drive[0]:"
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
if (-Not ($Drive)) { Throw "Error: missing drive letter!" }

if (!($DriveSize))
{
	$DriveSize = 100
}

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Throw "Must run powerShell as Administrator to perform these actions"     
}

# Create User
formatDrive
