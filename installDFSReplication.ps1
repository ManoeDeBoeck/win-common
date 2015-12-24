########################################################################################################
# Script  : /files/installDFSReplication.ps1
#
# Purpose : Installs the DFS replication service
# Author  : Ard-Jan Barnas
# Date    : 8/24/2015
########################################################################################################

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
	Write-Warning "Must run powerShell as Administrator to perform these actions"           
	return           
}

# Install DFS Replication feature	
Install-WindowsFeature FS-DFS-Replication

# Install DFS management console
Install-WindowsFeature RSAT-DFS-Mgmt-Con
