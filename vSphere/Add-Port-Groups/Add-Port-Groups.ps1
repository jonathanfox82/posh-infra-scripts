<#
.Synopsis
   This script creates port groups on a set of hosts.
.DESCRIPTION
   Used to add new standard port groups to a set of vSwitches within a datacenter.
   CSV import used to define cluster,vSwitch,VLANname,VLANid
.EXAMPLE
   .\Add-Port-Groups.ps1  -vCenter lonix-vcenter -PortGroupsCSV "PortGroups.csv"
 .VERSION 1.0
 Jonathan Fox
#>

Param(
  [Parameter(Mandatory=$True)]
  [string]$vCenter,
  [string]$PortGroupsCSV="PortGroups.csv"
)

# Import PowerCLI Modules 
Write-Host Importing VMware Modules
Get-Module -ListAvailable VM* | Import-Module

# Connect to vCenter
Write-Host Connecting to vCenter server $vCenter
Connect-ViServer -server $vCenter -ErrorAction Stop | Out-Null

$MyVLANFile = Import-CSV $PortGroupsCSV

ForEach ($VLAN in $MyVLANFile) {
    $MyCluster = $VLAN.cluster
    $MyvSwitch = $VLAN.vSwitch
    $MyVLANname = $VLAN.VLANname
    $MyVLANid = $VLAN.VLANid

    $MyVMHosts = Get-Cluster $MyCluster | Get-VMHost | Sort-Object Name | % {$_.Name}

    ForEach ($VMHost in $MyVMHosts) {
        Get-VirtualSwitch -VMHost $VMHost -Name $MyvSwitch | New-VirtualPortGroup -Name $MyVLANname -VLanId $MyVLANid
    }

}