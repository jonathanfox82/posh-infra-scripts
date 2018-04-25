<#
.Synopsis
   Set a standard syslog server
.DESCRIPTION
   # This script will set a Syslog Server all all ESXi hosts within a vCenter once connected.
.EXAMPLE
   Set-Syslog-Server.ps1 -vCenter myVcenter.domain.local -syslogServer 10.10.10.2
 .VERSION 1.0
#>

Param(
  [Parameter(Mandatory=$True)]
  [string]$vCenter,
  [Parameter(Mandatory=$True)]
  [string]$syslogServer
)

# Import PowerCLI Modules 
Write-Host Importing VMware Modules
Get-Module -ListAvailable VM* | Import-Module

# Connect to vCenter
Write-Host Connecting to vCenter server $vCenter
Connect-ViServer -server $vCenter -ErrorAction Stop | Out-Null

Write-Host "This script will change the Syslog Server on all hosts within a vCenter, restart Syslog, and open any required ports."

foreach ($myHost in Get-VMHost)
{
#Display the ESXi Host being modified
Write-Host '$myHost = ' $myHost
  
#Set the Syslog Server
Set-VMHostAdvancedConfiguration -Name Syslog.global.logHost -Value $syslogServer -VMHost $myHost
  
#Restart the syslog service
$esxcli = Get-EsxCli -VMHost $myHost
$esxcli.system.syslog.reload()
  
#Open firewall ports
Get-VMHostFirewallException -Name "syslog" -VMHost $myHost | set-VMHostFirewallException -Enabled:$true
}