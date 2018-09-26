Write-Host Importing VMware Modules
Get-Module -ListAvailable VM* | Import-Module

Connect-VIServer lcy-vcenter

Get-VM -Name hor*ext-* | 
    Select Name, @{N = "Avg Network Throughput MBPs"; E = {
        [math]::Round((Get-Stat -Entity $_ -Start (Get-Date).AddHours(-1) -Stat "net.throughput.usage.average" |
                    where {$_.Instance -eq ""} |
                    Measure-Object -Property Value -Average | Select -ExpandProperty Average) / 1KB, 2)
    }
}
