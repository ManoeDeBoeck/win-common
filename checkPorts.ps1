#-------------------------------------------------------------------------------------------------------
# Script  : checkPorts.ps1
# Purpose : Test an array of TCP and UDP ports and see if they are opened up
#
# Inputs  : TargetSystem  : Remote host to check
#			TestPorts	  : Dictionary containing list of UDP and TCP ports
#           PortqryPath   : Location of portqry.exe (optional - uses %path% to \windows\system32\cis)
#			(see common.yml)
#
#-------------------------------------------------------------------------------------------------------

# Parameters
[CmdletBinding()]
Param(
	[Parameter(Mandatory)]
	[string]$TargetSystem=$null,
	
	[Parameter(Mandatory)]
	[psobject]$TestPorts=$null,

	[Parameter(Mandatory=$false)]
	[psobject]$PortqryPath=$null
)

#-------------------------------------------------------------------------------------------------------

function Test-Port
{  
 
    Param(  
        [Parameter(  
            Position = 1,  
            Mandatory = $True,  
            ParameterSetName = '')]  
            [array]$port,  
        [Parameter(  
            Mandatory = $False,  
            ParameterSetName = '')]  
            [int]$TCPtimeout=2000,  
        [Parameter(  
            Mandatory = $False,  
            ParameterSetName = '')]  
            [int]$UDPtimeout=3000,             
        [Parameter(  
            Mandatory = $False,  
            ParameterSetName = '')]  
            [switch]$TCP,  
        [Parameter(  
            Mandatory = $False,  
            ParameterSetName = '')]  
            [switch]$UDP                                    
        )  


    If (!$tcp -AND !$udp) {$tcp = $True}  

    ForEach ($p in $port) 
    {  
        If ($tcp) 
        {    
            #Create object for connecting to port on computer  
            $tcpobject = new-Object system.Net.Sockets.TcpClient  

            #Connect to remote machine's port                
            Write-Verbose "Making TCP connection to $TargetSystem on port $p" 
            $connect = $tcpobject.BeginConnect($TargetSystem,$p,$null,$null) 
                 
            #Configure a timeout before quitting  
            $wait = $connect.AsyncWaitHandle.WaitOne($TCPtimeout,$false)  

            #If timeout  
            If(!$wait) 
            {  
                #Close connection  
                $tcpobject.Close() 
                Write-Warning "Port TCP $p Connection Timeout"
                Throw "Port TCP $p Connection Timeout"
            } 
            Else 
            {  
                $error.Clear()  
                $tcpobject.EndConnect($connect) | out-Null 
                     
                #If error  
                If($error[0])
                {  
                    #Begin making error more readable in report  
                    [string]$string = ($error[0].exception).message  
                    $message = (($string.split(":")[1]).replace('"',"")).TrimStart()  
                    $failed = $true  
                }  

                #Close connection      
                $tcpobject.Close()  

                #If unable to query port to due failure  
                If($failed)
                {  
                    Write-Warning "Port TCP $p filtered or not listening"
                    Throw $message
                } 
                Else
                {  
                    Write-Verbose "Port TCP $p open"
                }  
            }     

            #Reset failed value  
            $failed = $Null  
                    
        }    
              
        If ($udp) 
        {  
            #Create object for connecting to port on computer  
            $udpobject = new-Object system.Net.Sockets.Udpclient

            #Set a timeout on receiving message 
            $udpobject.client.ReceiveTimeout = $UDPTimeout 

            #Connect to remote machine's port                
            Write-Verbose "Making UDP connection to $TargetSystem on port $p" 
            $udpobject.Connect("$TargetSystem",$p) 

            #Sends a message to the host to which you have connected. 
            $a = new-object system.text.asciiencoding 
            $byte = $a.GetBytes("$(Get-Date)") 
            [void]$udpobject.Send($byte,$byte.length) 

            #IPEndPoint object will allow us to read datagrams sent from any source.  
            $remoteendpoint = New-Object system.net.ipendpoint([system.net.ipaddress]::Any,0) 
            Try 
            { 
                #Blocks until a message returns on this socket from a remote host. 
                $receivebytes = $udpobject.Receive([ref]$remoteendpoint) 
                [string]$returndata = $a.GetString($receivebytes)
                If ($returndata) {
                    Write-Verbose "Port UDP $p open"  
                    $udpobject.close()   
                }                       
            } 
            Catch
            { 
                If ($Error[0].ToString() -match "\bRespond after a period of time\b") 
                { 
                    #Close connection  
                    $udpobject.Close()  

                    #Make sure that the host is online and not a false positive that it is open 
                    If (Test-Connection -comp $TargetSystem -count 1 -quiet) 
                    { 
                        Write-Verbose "Port UDP $p open"  
                    } 
                    Else 
                    { 
                        <# 
                        It is possible that the host is not online or that the host is online,  
                        but ICMP is blocked by a firewall and this port is actually open. 
                        #> 
                        Write-Warning "Host maybe unavailable. Check if ICMP is blocked!"
                        Throw "Host maybe unavailable. Check if ICMP is blocked!"  
                    }                         
                } 
                ElseIf ($Error[0].ToString() -match "forcibly closed by the remote host" ) 
                { 
                    #Close connection  
                    $udpobject.Close()  
                    Write-Warning  "Port UDP $p connection timeout"
                    Throw "Port UDP $p connection timeout"
                } 
                Else 
                {                      
                    $udpobject.close() 
                } 
            }     
        }                                  
    }                  
}  

#----------------------------------------------------------------------------------------------

function IsAvailable
{
	# First let's see if the server is available
	If (Test-Connection -comp $TargetSystem -count 2 -quiet) 
	{ 
		Write-Host "$TargetSystem is available"
		return $true
	}

	Write-Warning "$TargetSystem unreachable. Check if it is on and ICMP port is opened!"
	Exit 1
}
	
#----------------------------------------------------------------------------------------------

# PortQry method (not used)
function CheckPorts([string[]]$res)
{  

	$PortsTCP = $TestPorts.PortsTCP
	foreach ($port in $PortsTCP)
	{
		Write-Host "Testing port TCP $port..."

		$cmd = "portqry -n " + $TargetSystem + " -e " + $port + " -p TCP"
		$output = Invoke-Expression $cmd
		$res = @($output | where {$_})
		$result = $res[-1]

		Write-Host $result
		if ($result -match "\bLISTENING\b")
		{
			Write-Host "Connection to port TCP $port successfull!"
		}
		else
		{
			Write-Warning "Connection to port TCP $port failed: $result"
			Exit 1
		}
	}

	$PortsUDP = @($TestPorts.PortsUDP)
	foreach ($port in $PortsUDP)
	{
		Write-Host "Testing port UDP $port..."

		$cmd = "portqry -n " + $TargetSystem + " -e " + $port + " -p UDP"
		$output = Invoke-Expression $cmd
		$res = $output | where {$_}
		$result = $res
		Write-Host $result
		
		if ($result -match "\bLISTENING\b")
		{
			Write-Host "Connection to port UDP $port successfull!"
		}
		else
		{
			Write-Warning "Connection to port UDP $port failed: $result"
			Exit 1
		}
	}
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

# Make sure we have all the parameters that we need
if (-Not($TargetSystem)) { Throw "missing TargetSystem" }
if (-Not($TestPorts)) { Throw "missing TestPort dictionary" }

# Check ports
If (IsAvailable)
{
#	CheckPorts $res
    Test-Port $TestPorts.portstcp -TCP
    Test-Port $TestPorts.portsudp -UDP
}
