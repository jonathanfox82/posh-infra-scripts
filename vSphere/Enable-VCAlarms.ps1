<#
.Synopsis
   Enable all vCenter alarms
.DESCRIPTION
   Re-enables all vCenter alarms after maintenance.
.EXAMPLE
   Enable-VCAlarms.ps1 -vCenter myVcenter.domain.local
 .VERSION 1.0
#>

Param
(
    [String]$vCenter="lcy-vcenter.corp.hertshtengroup.com"
)


$cred = Get-Credential

# Import PowerCLI Modules
Get-Module -ListAvailable VM* | Import-Module

# Connect to vCenter
Connect-VIServer -Server $vCenter -Credential $cred


Write-Host "--------------------------------"
Write-Host "Enabling vCenter alarms"
Write-Host "--------------------------------"

$clusters = Get-Cluster

$alarmMgr = Get-View AlarmManager


ForEach ($cluster in $clusters) {
    Write-Host Enabling Alarms for $cluster.Name
    $alarmMgr.EnableAlarmActions($cluster.Extensiondata.MoRef,$true)
}

$hosts = Get-VMHost
ForEach ($esx in $hosts) {
    Write-Host Enabling Alarms for $esx.Name
    $alarmMgr.EnableAlarmActions($esx.Extensiondata.MoRef,$true)
}

$datastores = Get-Datastore

ForEach ($datastore in $datastores) {
    Write-Host Enabling Alarms for $datastore.Name
    $alarmMgr.EnableAlarmActions($datastore.Extensiondata.MoRef,$true)
}

# Exit
Disconnect-VIServer -Confirm:$false
