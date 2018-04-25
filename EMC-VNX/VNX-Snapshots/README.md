# VNX-Toolkit
Random Scripts for EMC VNX PowerShell


## VNX-Snaps.PS1
http://blog.superautomation.co.uk/2017/05/automating-vnx-snapshots-with-emc.html

Requires - EMC Storage Integrator Powershell (ESIPSToolkit) Version 5.0.1.3

The script is intended to be scheduled to run on a daily basis and will automatically clear any snapshots older than the 'expireDays' parameter. The script will detect which type of LUN is passed in and will create a pool based snapshot for pool LUNs and a SnapView snapshot for RAID based LUNs.

### Example

    $connectionStringPri = @{
        "Username"="admin";
        "Password"="password";
        "SpaIpAddress"="192.168.50.1";
        "SpbIpAddress"="192.168.50.2";
        "Port"="443";
        "UserFriendlyName"="Primary SAN"
    };

    $connectionStringSec = @{
        "Username"="admin";
        "Password"="password";
        "SpaIpAddress"="192.168.51.1";
        "SpbIpAddress"="192.168.51.2";
        "Port"="443";
        "UserFriendlyName"="Secondary SAN"
    };

    [Array]$sanArray = (
        $connectionStringPri, 
        $connectionStringSec
    )

    [Array]$targetLuns = (
        "LUN1",
        "LUN2",
        "LUN3"
    )

    . .\VNX-Snaps.PS1 -expireDays 3 -targetLuns $targetLuns -sanArray $sanArray
