<#
.Synopsis
   Shutdown script for remote office
.DESCRIPTION
   This can be used for our remote IT staff to shut their remote office locations down safely before any power maintenance.
   Users is prompted to select and office and then has to confirm all the shutdown activities manually.
.EXAMPLE
   Shutdown-Office.ps1
.EXAMPLE
   Shutdown-Office.ps1 -vCenter yourvcenterfqdn.domain.local
 .VERSION 1.0
 Jonathan Fox
#>


Param
(
    [String]$vCenter="lcy-vcenter.corp.hertshtengroup.com",
    [bool]$Whatif= $false
)
function Powerdown-Office ($DatacenterName)
{
    # Get Cluster object
    $cluster = Get-Datacenter $DatacenterName | Get-Cluster
    
    # Get Hosts object
    $Hosts = Get-VMHost -Location $DatacenterName

    # Disable vCenter alarms
    Write-Host "--------------------------------"
    Write-Host "Disabling vCenter alarms"
    Write-Host "--------------------------------"
    $alarmMgr = Get-View AlarmManager
    $alarmMgr.EnableAlarmActions($cluster.Extensiondata.MoRef,$false)

    ## Shut VMs down and wait til complete
    Write-Host "--------------------------------"
    Write-Host "Shutting down Virtual Machines"
    Write-Host "--------------------------------"
    $counter = 0
    $timeout = 300
    do {
        # Get VMs object
        $VMs = Get-VMList ($DatacenterName) | where {$_.powerstate -eq "poweredon"}
        Write-Host The following VMs are powered on:
        Write-Host $VMs | fw 
        if ($VMs)
        {
            if ($counter -eq 0) {
                $VMs | where {$_.Guest.State -eq "Running"} | Shutdown-VMGuest -Confirm:$false
                $VMs | where {$_.Guest.State -eq "NotRunning"} | Stop-VM -Confirm:$false
            }
            Write-Host "VMs are still powered on, waiting "($timeout-$counter)" seconds longer"
            $counter = $counter + 10
            Sleep 10
        }
    }
    while ($counter -lt $timeout) -or (($VMs.count) -ne 0)

    if ($counter -ge $timeout) {
        Write-Host "Some VMs failed to shut down gracefully, powering down now"
        $VMs | where {$_.powerstate -eq "poweredon"} | Stop-VM -Confirm:$false
    }
    # Enter Maintenance Mode on all hosts
    Write-Host "--------------------------------"
    Write-Host "Entering host maintenance mode"
    Write-Host "--------------------------------"
    Set-VMHost -VMHost $Hosts -State "Maintenance" -Confirm:$false

    # Shut hosts down
    Write-Host "--------------------------------"
    Write-Host "Shutting down hosts"
    Write-Host "--------------------------------"
    Stop-VMHost -VMHost $Hosts -Confirm:$false

    # Exit
    Disconnect-VIServer -Confirm:$false
    Exit
}

function Get-VMList {
    Param
    (
        [String]$DataCenter
    )
    $VMList = Get-VM -Location $Datacenter
    Return $VMList
}

function Show-Menu
{
     param (
           [string]$Title = "Choose an option from the list",
           [hashtable]$MenuOptions
     )
     cls
     Write-Host "================ $Title ================"
     
     $MenuOptions.GetEnumerator() | sort -Property Name | ForEach-Object{
     $message = '{0}: Press {0} for option {1}' -f $_.key, $_.value
     Write-Output $message
    }
}



# Variable Block #
########################################
$emailFrom = "noreply@hertshtengroup.com"
$emailTo = "server.engineering@hertshtengroup.com"
########################################


Write-Host Importing VMware.VimAutomation.Core Module 

# Import PowerCLI Modules 
Get-Module VM* | Import-Module

Write-Host Connecting to vCenter server $vCenter
# Connect to vCenter

Connect-VIServer -Server $vCenter

$i=1
$selection = ""
# Create an ordered hashtable to contain the office selections
$OfficeList = [ordered]@{}

# Exclude our main datacenter (will move this to a variable exclude pattern later)
Get-Datacenter | Where Name -NotMatch Interxion | % {
    $OfficeList.add($i, $_.Name)
    $i++
}

do
{
     Show-Menu -Title "Office power down Menu, Select an office to shut down" -MenuOptions $OfficeList
     $selection = Read-Host "Please make a selection or press q to quit"

     # Is this an Integer?
     if ($selection -match "^\d+$")
     {
         if (($OfficeList.Keys) -contains $selection) {
            $OfficeName = ($OfficeList.[int]$selection)
            $User = ($env:UserName)
            Write-Host  $User You have chosen to shut down the office $OfficeName. -ForegroundColor White -BackgroundColor Red

            # A chance to change your mind
            write-host -nonewline "Continue? (Y/N) "
            $response1 = read-host
            if ( $response1 -ne "Y" ) { exit }

            Write-Host THIS SCRIPT IS ACTIVE THE OFFICE WILL BE POWERED DOWN -ForegroundColor White -BackgroundColor Red

            # One last chance to change your mind
            write-host -nonewline "Are you sure? (Y/N) "
            $response2 = read-host
            if ( $response2 -ne "Y" ) { exit }

            $body = "$User has initiated an office shutdown for $OfficeName"

            Write-Host "Sending email notification"
            Send-MailMessage -To $emailTo -From $emailFrom "noreply@hertshtengroup.com" -Subject "$OfficeName power down initiated by $User" -SmtpServer "smtp.corp.hertshtengroup.com" -Body $body

            Powerdown-Office ($OfficeList.[int]$selection)
            Read-Host "Press enter key to exit..."
            Exit
         }
     }
}
until ($selection -eq 'q')