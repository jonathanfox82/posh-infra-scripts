<#
.Synopsis
   This script creates a vSwitch and port groups on a host.
.DESCRIPTION
   Another method to add multiple port groups at once without a CSV file being required.
.EXAMPLE
   .\Create-vSwitches.ps1  -vCenter lcy-vcenter -clusterName London -vSwitchName vSwitch4 -physicalnic vmnic6
 .VERSION 1.0
 Jonathan Fox
#>
Param(
    [Parameter(Mandatory=$True)]
    [string]$vCenter,  
    [Parameter(Mandatory=$True)]
    [string]$clusterName,   
    [Parameter(Mandatory=$True)]
    [string]$vSwitchName,
    [string]$physicalnic,
    [int[]]$vlans = '2,10,35,110,115,117,118,130,131,181,185,190,199,200,201,202,230'
)

# Import PowerCLI Modules 
Write-Host Importing VMware Modules
Get-Module -ListAvailable VM* | Import-Module

# Connect to vCenter
Write-Host Connecting to vCenter server $vCenter
Connect-ViServer -server $vCenter -ErrorAction Stop | Out-Null

Get-Cluster -Name $clusterName | Get-VMHost | ForEach-Object {
    $sw = New-VirtualSwitch -Name $vSwitchName -VMHost $esx -Nic $physicalnic -Confirm:$false
    $vlans | ForEach-Object { New-VirtualPortGroup -Name "VLAN$($_)" -VLanId $_ -VirtualSwitch $sw -Confirm:$false }
}