##################################################################################################
# Script: Restart-Server.ps1
# 
# Restarts Windows VM
##################################################################################################

# Remove any previous scheduled task
function RemoveScheduledTask
{
	$ErrorActionPreference = "SilentlyContinue"
	if (Get-ScheduledTask -TaskName "Ansible Restart computer")
	{
		$ErrorActionPreference = "Stop"
		Unregister-ScheduledTask -TaskName "Ansible Restart computer" -Confirm:$false
	}

	$ErrorActionPreference = "Stop"
}

# Create a new task and reboot
function CreateScheduledTask
{
	$immediate = (get-date).AddSeconds(10)
	$trigger = New-ScheduledTaskTrigger -Once -At $immediate
	$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
	$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
	
	$program =  "C:\WINDOWS\system32\shutdown.exe"
	$parms = "-r -f -t 01"

	$act = New-ScheduledTaskAction -Execute $program -Argument $parms

	Register-ScheduledTask `
	-TaskName "Ansible Restart computer" `
	-Settings $settings `
	-Action $act `
	-Trigger $trigger `
	-Principal $principal
}

#----------------------------------------------------------------------------------------------
# MAIN
#----------------------------------------------------------------------------------------------

# Enable verbose output
$VerbosePreference = "Continue"

# Setup error handling.
Trap
{
    $_
    Exit 1
}
$ErrorActionPreference = "Stop"

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Write-Warning "Must run powerShell as Administrator to perform these actions"           
	return           
}

# Remove any previous scheduled task
RemoveScheduledTask

# Create a new task and reboot
CreateScheduledTask
