# ------------------------------------------------------------------------------------------------------------------
# Script: ConfigureNetworking.ps1
# Configures Network Settings
#
# Parameters:
# -----------
# DNSServers	: Array of ip addresses 
# ------------------------------------------------------------------------------------------------------------------

# Parameters
[CmdletBinding()]
Param(
	[Parameter(Mandatory)]
	[string]$Placement=$null,

	[Parameter(Mandatory)]
	[psobject]$Topology=$null,

	[Parameter(Mandatory=$false)]
	[switch]$ReverseDNS,

	[Parameter(Mandatory=$false)]
	[switch]$UseParentDNS
	)

#----------------------------------------------------------------------------------------

# Convert DHCP enabled adapter to static IPAddressing
Function ConfigureNetworking
{
	# Make sure we run as admin            
	$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
	$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
	if (-not($IsAdmin))            
	{            
		Throw "Must run powerShell as Administrator to perform these actions"     
	}
	
	
	# Convert DHCP assigned address to static IP
	try
	{
		# Get the adapters that are enabled and configured for DHCP
		$Adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration | where {$_.IPEnabled -eq $true -and $_.DHCPEnabled -eq $true}
		
		foreach($NIC in $Adapters) 
		{
			$IPAddress = ($NIC.IPAddress[0])
			$Gateway = $NIC.DefaultIPGateway[0]
			$Netmask = $NIC.IPSubnet[0]
			
			$NIC.EnableStatic($IPAddress, $Netmask)
			$NIC.SetGateways($Gateway)
		}

		# The DNS configuration is set in a separate loop, so we can update DNS in the event the wrong DNS servers
		# are configured and need to be updated, since the first query only returns DHCP enabled adapters
		
		# Get the adapters that are enabled and not configured for DHCP so we can update the DNS server settings
		$Adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration | where {$_.IPEnabled -eq $true}
		
		foreach($NIC in $Adapters) 
		{
			# Update DNS settings
			Write-Verbose "Setting DNS settings to $DNSServers"
			$NIC.SetDNSServerSearchOrder($DNSServers)
			$NIC.SetDynamicDNSRegistration("TRUE")
		}
	}
	catch
	{
		Throw "Failed to convert DHCP address to static IP because $($_.Exception.Message)"
	}
}

#----------------------------------------------------------------------------------------
# Set up error handling
$VerbosePreference = "Continue"

# Setup error handling.
Trap
{
    Write-Error $_
    Exit 1
}
$ErrorActionPreference = "Stop"

#----------------------------------------------------------------------------------------
# Main
#----------------------------------------------------------------------------------------

# Make sure we have all the parameters that we need
if (-Not ($Placement)) { Throw "Error: missing Placement parameter!" }
if (-Not ($Topology.forest.primaryDNS)) { Throw "Error: missing forest primary DNS parameter in Topology!" }
if (-Not ($Topology.forest.secondaryDNS)) { Throw "Error: missing forest secondaryDNS parameter in Topology!" }
if (-Not ($Topology.domain.primaryDNS)) { Throw "Error: missing domain primary DNS parameter in Topology!" }
if (-Not ($Topology.domain.secondaryDNS)) { Throw "Error: missing domain secondaryDNS parameter in Topology!" }

Write-Verbose "Placement: $Placement"

# Set the domain dictionary to use
if ($Placement -eq "forest") {
	if ($UseParentDNS)
	{
		$DNSServers = @($Topology.forest.primaryParentDNS,$Topology.forest.secondaryParentDNS)
	}
	else
	{
		if ($ReverseDNS)
		{
			$DNSServers = @($Topology.forest.secondaryDNS,$Topology.forest.primaryDNS)
		}
		else
		{
			$DNSServers = @($Topology.forest.primaryDNS,$Topology.forest.secondaryDNS)
		}
	}
}
elseif ($Placement -eq "domain")
{
	if ($UseParentDNS)
	{
		$DNSServers = @($Topology.domain.primaryParentDNS,$Topology.domain.secondaryParentDNS)
	}
	else
	{
		if ($ReverseDNS)
		{
			$DNSServers = @($Topology.domain.secondaryDNS,$Topology.domain.primaryDNS)
		}
		else
		{
			$DNSServers = @($Topology.domain.primaryDNS,$Topology.domain.secondaryDNS)
		}
	}
}
else
{
	Throw "Error: Placement misconfigured. Needs to specify domain or forest. Current value: $Placement"
}

# Configure network settings
ConfigureNetworking 



