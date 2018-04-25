<#
.DESCRIPTION
   This script migrates VMs from one port group to another.
.EXAMPLE
   .\Migrate-Port-Group.ps1  -vCenter lcy-vcenter -Cluster London -OldPG VLAN10 -NewPG VLAN11
 .VERSION 1.0
 Jonathan Fox
#>

Param(
    [Parameter(Mandatory=$True)]
    [string]$vCenter,   
    [Parameter(Mandatory=$True)]
    [string]$Cluster,
    [Parameter(Mandatory=$True)]
    [string]$OldPG,
    [Parameter(Mandatory=$True)]
    [string]$NewPG
            
)
# Import PowerCLI Modules 
Write-Host Importing VMware Modules
Get-Module -ListAvailable VM* | Import-Module

# Connect to vCenter
Write-Host Connecting to vCenter server $vCenter
Connect-ViServer -server $vCenter -ErrorAction Stop | Out-Null

Get-Cluster $Cluster | Get-VM |Get-NetworkAdapter |Where {$_.NetworkName -eq $OldPG } |Set-NetworkAdapter -NetworkName $NewPG -Confirm:$false