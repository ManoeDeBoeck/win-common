########################################################################################################
# Script  : configureSitesAndLinks.ps1
# Purpose : Configure the domain sites, site links, and subnets
#
# Inputs  : Topology		- AD Topology of Sites
#           DomainConfig	- Holds current site and subnet information
#           DefaultSites	- (optional) List of all known sites to precreate
#			(see common.yml)
#
########################################################################################################

# Parameters
[CmdletBinding()]
Param(
	[Parameter(Mandatory)]
	[psobject]$Topology=$null,
		
	[Parameter(Mandatory)]
	[psobject]$Site=$null,
		
	[Parameter(Mandatory=$false)]
	[psobject]$DefaultSites=$null
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

	if ([ADSI]::Exists("LDAP://$path"))
	{
		return $true
	}
	
	return $false
}


#----------------------------------------------------------------------------------------------
# Build hash table for site links from Sites dictionary
function BuildSiteLinkHash
{
    Param( [hashtable]$hash, [string]$key, [string[]]$sitelinks, [int]$cost, [int]$interval )

	try
	{
		if (-Not ($hash.ContainsKey($key))) 
		{
			$hash.Add($key, @{links=$sitelinks;cost=$cost;interval=$interval})
		}
		else
		{
			foreach ($link in $sitelinks)
			{
				if (-Not ($hash[$key].links.Contains($link))) {
					write-host "*** $link"
					$hash[$key].links += $link
				}
			}
		}
	}
	catch
	{
		Throw "Error in function: BuildSiteLinkHash - $key, $cost, $interval"
	}
}

#----------------------------------------------------------------------------------------------
# Configure AD Sites and Subnets
Function ConfigureSites
{
	# Get the forest administrator credential object
	$Credential = GetEnterpriseCredential
	
	foreach ($s in $Sites.Keys)
	{
		# Check required parameters
		if (-Not ($Sites[$s].location)) { Throw "Missing location value in $s" }
		if ((-Not ($Sites[$s].subnets)) -Or (-Not($Sites[$s].subnets[0]))) { Throw "Missing subnet value in $s" }

		# Get values from dictionary
		$location = $Sites[$s].location
		$subnets = $Sites[$s].subnets
		
		# Create AD replication site
		$sitefilter = [scriptblock]::create("Name -like '$s*'")
		if (-Not (Get-ADReplicationSite -Filter $sitefilter))
		{
			try	
			{ 
				# Create new AD replication site
				Write-Verbose "Creating new AD site $s"
				
				New-ADReplicationSite `
				-Name $s `
				-Credential $Credential
			}
			catch
			{
				Throw "Error creating new AD site $sitename because $($_.Exception.Message)"
			}
		}
		else
		{
			# Replication site already exists"
			Write-Verbose "AD Replication Site $s already exists. Skipping"
		}

		# Create subnets
		foreach ($subnet in $subnets)
		{
			$subnetfilter = [scriptblock]::create("Name -like '$subnet*'")
			if (-Not (Get-ADReplicationSubnet -Filter $subnetfilter))
			{
				#Create new AD subnet
				Write-Verbose "Creating AD subnet $subnet for site $s"
				
				try	
				{ 
					New-ADReplicationSubnet `
					-Credential $Credential `
					-Name $subnet `
					-Site $s `
					-Location $location 
				}
				catch
				{
					Throw "Error creating new AD subnet $subnet because $($_.Exception.Message)"
				}
			}
			else
			{
				# Subnet already exists. Update existing information
				Write-Verbose "Subnet $subnet already exists. Updating existing information."

				try 
				{ 
					Set-ADReplicationSubnet `
					-Credential $Credential `
					-Identity $subnet `
					-Site $s `
					-Location $location 
				}
				catch
				{
					Throw "Error updating AD subnet $subnet because $($_.Exception.Message)"
				}
			}
		}
	}
}

#----------------------------------------------------------------------------------------------
# Configure AD Site Links
function ConfigureSiteLinks
{
	# Get the forest administrator credential object
	$Credential = GetEnterpriseCredential
	
	# Build site links hash table
	foreach ($s in $Sites.Keys)
	{
		# Check that we have cost and interval parameters for the primary sites
		if ($s -eq $primarySite -Or $s -eq $secondarySite)
		{
			if (-Not ($Site.sitereplication[$s].cost)) { Throw "Missing cost parameter for site $s" }
			if (-Not ($Site.sitereplication[$s].interval)) { Throw "Missing interval parameter for site $s" }
		}
		
		if ($s -ne $primarySite)
		{
			# Create the sitelink using the primarySite and current site
			$strId = $primarySite + "/" + $s
			$sitelinks = $Sites.Keys | ? { $_ -eq $s  -Or $Sites[$_].isprimary -eq $True}
			$cost = $Site.sitereplication[$primarySite].cost
			$interval = $Site.sitereplication[$primarySite].interval

			if ($secondarySite -And $s -eq $secondarySite)
			{
				$cost = $Site.sitereplication[$secondarySite].cost
				$interval = $Site.sitereplication[$secondarySite].interval
			}
			BuildSiteLinkHash $hashLinks $strId $sitelinks $cost $interval

			# Create the sitelink with the secondary site
			if ($secondarySite -And $s -ne $secondarySite)
			{
				# Create the sitelink using the secondarySite and current site
				$strId = $secondarySite + "/" + $s
				$sitelinks = $Sites.Keys | ? { $_ -eq $s -Or $Sites[$_].issecondary -eq $True}
				$cost = $Site.sitereplication[$secondarySite].cost
				$interval = $Site.sitereplication[$secondarySite].interval
				BuildSiteLinkHash $hashLinks $strId $sitelinks $cost $interval
			}
		}   
	}

	
	# create the AD site links from hashLinks
	foreach ($identity in $hashLinks.Keys)
	{	
		$links = $hashLinks[$identity].links
		$cost = $hashLinks[$identity].cost
		$interval = $hashLinks[$identity].interval
		
		$sitelinkfilter = [scriptblock]::create("Name -eq '$identity'")
		if (-Not (Get-ADReplicationSiteLink -Filter $sitelinkfilter))
		{
			try
			{
				# Create new AD replication site link
				Write-Verbose "Creating new AD replication site link $identity"
				
				New-ADReplicationSiteLink `
				-Name $identity `
				-SitesIncluded $links `
				-Credential $Credential `
				-ReplicationFrequencyInMinutes $interval `
				-Cost $cost `
				-InterSiteTransportProtocol IP
			}
			catch
			{
				Throw "Error creating new AD sitelink $identity because $($_.Exception.Message)"
			}
		}
		else
		{
			# Site link already exists. Skipping
			Write-Verbose "Site replication link $identity already exists. Skipping."
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

# Make sure we run as admin            
$usercontext = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()            
$IsAdmin = $usercontext.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")                               
if (-not($IsAdmin))            
{            
	Throw "Must run powerShell as Administrator to perform these actions"     
}

# Make sure we have all the parameters that we need in DomainConfig
if (-Not ($Site.sitename)) { Throw "Error: missing SiteName parameter in SiteConfig!" }
if (-Not ($Site.subnets)) { Throw "Error: missing Subnets parameter in SiteConfig!" }
if (-Not ($Site.location)) { Throw "Error: missing Location parameter in SiteConfig!" }
if (-Not ($Site.sitereplication)) { Throw "Error: missing SiteReplication parameter in SiteConfig!" }
if (-Not ($Topology.primarysites)) { Throw "Error: missing primarySites parameter in Topology!" }
if (-Not ($Topology.forest.password)) { Throw "Error: missing Password parameter in Topology!" }

# Determine primary and secondary sites for the AD topology
$primarySite = $Topology.primarysites.keys | ? { $Topology.primarysites[$_].isprimary -eq "True"}
$secondarySite = $Topology.primarysites.keys | ? { $Topology.primarysites[$_].issecondary -eq "True"}
if (-Not ($primarySite)) { Throw "missing primary site in Sites dictionary" }

# Create empty hash table
$hashLinks = @{}

# Make sure the sites in Topology have a match in SiteConfig
$Sites = $Topology.primarysites
foreach ($s in $Sites.keys) 
{
	Write-Host $s
	if (-Not($Site.sitereplication[$s])) { Throw "Error: $s not found in Site dictionary!" }
}

# Add the given sitename, subnet(s), and site location to the Topology-sites hashtable
if (-Not ($Sites.Contains($Site.sitename))) 
{
	Write-Host "Adding " + $Site.sitename
	$Sites.Add( $Site.sitename, @{subnets=$Site.subnets.servicecloud;location=$Site.location} )
}

# Run main functions
ConfigureSites
ConfigureSiteLinks
