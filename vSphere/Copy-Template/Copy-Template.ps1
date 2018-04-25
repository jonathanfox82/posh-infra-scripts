<#
.Synopsis
   This script copies a central template to all other datacenters
.DESCRIPTION
   This can be used for our remote IT staff to shut their remote office locations down safely before any power maintenance.
   Users is prompted to select and office and then has to confirm all the shutdown activities manually.
.EXAMPLE
   .\Copy-Template.ps1  -vCenter lcy-vcenter -Template "RHEL6.5" -SourceFolder "London" -DatacenterCSV .\sites.csv -StdPortGroup "VLAN10 - Servers"
 .VERSION 1.0
 Jonathan Fox
#>

Param(
  [Parameter(Mandatory=$True)]
  [string]$vCenter,   
  [Parameter(Mandatory=$True)]
  [string]$Template,
  [Parameter(Mandatory=$True)]
  [string]$SourceFolder="UK",
  [Parameter(Mandatory=$True)]
  [string]$DatacenterCSV,
  # Destination template standard port group
  [string]$StdPortGroup
)
$stdpg = $StdPortGroup
$date = Get-Date -format yyyyMMdd

# Import PowerCLI Modules 
Write-Host Importing VMware Modules
Get-Module -ListAvailable VM* | Import-Module

# Connect to vCenter
Write-Host Connecting to vCenter server $vCenter
Connect-ViServer -server $vCenter -ErrorAction Stop | Out-Null

# Source Folder
$sourceTemplate = Get-Template -name $Template -Location $SourceFolder -ErrorAction SilentlyContinue  
If ($sourceTemplate){  
     Write "Source Template $Template found in $SourceFolder"  
}  
Else {  
     Write "Source Template $Template not found in location $SourceFolder"  
     Exit
}

# Import sites list CSV to an array
$siteList = Import-CSV $DatacenterCSV
$taskTab = @{}

foreach ($item in $siteList) {
# Map variables
$datacenter = $item.datacenter

# Check if Datacenter exists
$DatacenterExists = Get-Datacenter -Name $datacenter -ErrorAction SilentlyContinue
If ($DatacenterExists){  
     Write "$datacenter - Input validated"  
}  
Else {  
    Write "$datacenter - Errors in input file"
    Exit
}

$strNewTemplateName = $sourceTemplate    # name for new template in remote datacenters

# Select a cluster in the datacenter to deploy to
$cluster = Get-Datacenter -Name $datacenter | Get-Cluster | Select-Object -first 1

# Select the first host in the datacenter to deploy to
$vmhost = Get-Datacenter -Name $datacenter |  Get-VMHost | Select-Object -first 1

# Select the Templates folder in that datacenter
$location = Get-Datacenter -Name $datacenter | Get-Folder -Name 'Templates'

# Select the largest VMFS datastore in that datacenter for the templates to go on.
$datastore = Get-Datacenter -Name $datacenter | Get-datastore | where {$_.type -eq "VMFS"} | Sort-Object FreeSpaceGB -desc | Select-Object -first 1

# If it already exists at this location, skip this 
If ($location | Get-Template -Name $strNewTemplateName -ErrorAction SilentlyContinue  ) {
  Write "Template $strNewTemplateName already copied to $datacenter"
}
Else {
  Write "Copying Template $strNewTemplateName to $datacenter"
  $taskTab[(New-VM -Name $strNewTemplateName -Template $sourceTemplate -VMHost $vmhost -Datastore $datastore -Location $location -Description "Template copied on $date" -RunAsync).Id] = $strNewTemplateName
}

}
# Set the port group of the new VM and mark each VM as a Template once the tasks complete
$runningTasks = $taskTab.Count
while($runningTasks -gt 0){
Get-Task | % {
if($taskTab.ContainsKey($_.Id) -and $_.State -eq "Success"){
Get-VM $taskTab[$_.Id] | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $stdpg -Confirm:$false
Get-VM $taskTab[$_.Id] | Set-VM -ToTemplate -Confirm:$false
$taskTab.Remove($_.Id)
$runningTasks--
}
elseif($taskTab.ContainsKey($_.Id) -and $_.State -eq "Error"){
$taskTab.Remove($_.Id)
$runningTasks--
}
}
Start-Sleep -Seconds 15
}
