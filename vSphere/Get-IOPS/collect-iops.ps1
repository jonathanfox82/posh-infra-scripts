####################################################################
# Uses vCenter Real Time Performance Stats to
# collect real time counters for Read/Write IOPS for All VMs/Disks 
# and writes data to file
#
# http://www.vhersey.com/
#
####################################################################
# vCenter Server

Param(
    [Parameter(Mandatory=$True)]
    [String]$vCenter,
    [Parameter(Mandatory=$True)]
    [String]$Datacenter,
    [String]$OutputFile='C:\Utilities\Collect-IOPS.csv',
    [Int]$Samples=360,
    # 1 Minute = 3
    # 1 Hour = 180
    # 1 Day = 4320

    [Int]$Interval=20
)

Get-Module -ListAvailable VM* | Import-Module



################ HERE WE GO ####################
# Create New File
New-Item $OutputFile -type file -force
#Add Column Headers to File
Add-Content $OutputFile "TimeStamp,VM,Disk,Datastore,ReadIOPS,ReadLatency,WriteIOPS,WriteLatency"

# Connect to vCenter
Connect-Viserver $vCenter

Write-Host "Collecting $samples Samples"

function Collect-IOPS {

   #Get VMs
   $vms = Get-Datacenter $Datacenter | Get-VM

   #IOPS - Thanks to LucD http://www.lucd.info/2011/04/22/get-the-maximum-iops/
   # https://www.vmware.com/support/developer/converter-sdk/conv61_apireference/virtual_disk_counters.html
   $metrics = "virtualdisk.numberreadaveraged.average","virtualdisk.numberwriteaveraged.average","virtualdisk.totalReadLatency.average","virtualdisk.totalWriteLatency.average"
   $stats = Get-Stat -Realtime -Stat $metrics -Entity ($vms | Where {$_.PowerState -eq "PoweredOn"}) -MaxSamples 1
   $Interval = $stats[0].IntervalSecs
 
   $hdTab = @{}
      foreach($hd in (Get-Harddisk -VM ($vms | Where {$_.PowerState -eq "PoweredOn"}))){
          $controllerKey = $hd.Extensiondata.ControllerKey
          $controller = $hd.Parent.Extensiondata.Config.Hardware.Device | where{$_.Key -eq $controllerKey}
          $hdTab[$hd.Parent.Name + "/scsi" + $controller.BusNumber + ":" + $hd.Extensiondata.UnitNumber] = $hd.FileName.Split(']')[0].TrimStart('[')
   }

   $iops = $stats | Group-Object -Property {$_.Entity.Name},Instance

   foreach ($collected in $iops) {
       $sorted = $collected.Group | Sort-Object MetricId | Group-Object -Property Timestamp
       $readios = $sorted.Group[0].Value 
       $writeios = $sorted.Group[1].Value 
       $readlatency = $sorted.Group[2].Value 
       $writelatency = $sorted.Group[3].Value  
       $timestamp = $collected.Group | Group-Object -Property Timestamp
       $ts = $timestamp.Name
       $vmname = $collected.Values[0]
       $vmdisk = $collected.Values[1]
       $ds = $hdTab[$collected.Values[0] + "/"+ $collected.Values[1]]
       #TimeStamp, VM, Disk, Datastore, Read IOPS, ReadLatency, Write IOPS, Write Latency
       $line = "$ts,$vmname,$vmdisk,$ds,$readios,$readlatency,$writeios,$writelatency"
       #Write-Host $line
       Add-Content $OutputFile "$line"
   } 

}

For ($i = 1; $i -le $samples; $i+=1) {
    Write-Host "Collecting Sample $i"
    Collect-IOPS
    Write-Host "Sleeping for $Interval"
    start-sleep -s $Interval
}

Disconnect-Viserver $vcenter -Confirm:$false -WarningAction SilentlyContinue

#################################################################################
# Example Powershell to get Total Reads and Writes Per Sample 
# $iopsdata = Import-CSV .\Collect-IOPS.csv
# $iopspersample = $iopsdata | Select-Object -Property * -Exclude Disk,VM,Datastore | Group-Object -Property TimeStamp,Instance | %{
#    New-Object PSObject -Property @{
#        TimeStamp = $_.Name
#        ReadIOPS = ($_.Group.ReadIOPS | Measure-Object -Sum).Sum
#        WriteIOPS = ($_.Group.WriteIOPS | Measure-Object -Sum).Sum
#    }
#}
#################################################################################
