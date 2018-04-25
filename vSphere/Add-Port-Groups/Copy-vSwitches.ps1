<#
.Synopsis
   This script copies vSwitch information from a template host.
.DESCRIPTION
    Useful when we don't have Host Profiles or Distributed Virtual Switches but want to copy a large number of port groups.
.EXAMPLE
   .\Copy-vSwitches.ps1  -vCenter lcy-vcenter -BaseHost lcy-esx01 -DestHost chi-esx01 -vSwitch vSwitch1
 .VERSION 1.0
 Jonathan Fox
#>

Param(
    [Parameter(Mandatory=$True)]
    [string]$vCenter,   
    [Parameter(Mandatory=$True)]
    [string]$BaseHost,
    [Parameter(Mandatory=$True)]
    [string]$DestHost,
    [Parameter(Mandatory=$True)]
    [string]$vSwitch
)
# Import PowerCLI Modules 
Write-Host Importing VMware Modules
Get-Module -ListAvailable VM* | Import-Module

# Connect to vCenter
Write-Host Connecting to vCenter server $vCenter
Connect-ViServer -server $vCenter -ErrorAction Stop | Out-Null

$BASEHost = Get-VMHost -Name $BaseHost
$NEWHost = Get-VMHost -Name $DestHost

$BASEHost | Get-VirtualSwitch -Name $vSwitch
 {
   $_ |Get-VirtualPortGroup |Foreach {
       If (($NEWHost |Get-VirtualPortGroup -Name $_.Name)-eq $null){
           Write-Host "Creating Portgroup $($_.Name)"
           $NewPortGroup = $NEWHost |Get-VirtualSwitch -Name vSwitch1 |New-VirtualPortGroup -Name $_.Name-VLanId $_.VLanID
        }
    }
}