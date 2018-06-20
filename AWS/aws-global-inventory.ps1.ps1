Import-Module AWSPowerShell

$regions = Get-AWSRegion

$EC2Array =@()
$RDSArray =@()
$subnets = Get-EC2Subnet

foreach ($region in $regions)
{
    Write-Host "Checking $($region.name) for AWS resources"

    $instances = (Get-EC2Instance -Region $region.Region).instances
    foreach ($i in $instances)
    {
        $iName = ($i.tags | Where-Object -Property key -EQ 'Name').Value
        $iInstanceId = $i.instanceID
        $iSubnetID = $i.iSubnetID
        $iAZ = ($subnets | Where-Object -Property subnetid -EQ $isubnetID).AvailabilityZone
        $EC2Obj = New-Object -TypeName System.Management.Automation.PSObject -Property ([ordered]@{
                'Instance Name' = $iName;
                'InstanceID' = $iInstanceId;
                'InstanceType' = $i.InstanceType;
                'Platform' = $i.Platform;
                #'Subnet' = $i.SubnetId;
                'AZ' = $iAZ;
                #'PrivateDnsName' = $i.PrivateDnsName;
                'PrivateIpAddress' = $i.PrivateIpAddress;
                'PublicDnsName' = $i.PublicDnsName;
                'PublicIpAddress' = $i.PublicIpAddress;
                'State' = $i.state.Name;
                'Region' = $region.Name;
                'Role' = $i.Tag | ? { $_.key -eq "Role" } | select -expand Value;
                'Service' = $i.Tag | ? { $_.key -eq "Service" } | select -expand Value;
            })
        $EC2Array += $EC2Obj
        }
    
    $RDSInstances =  Get-RDSDBInstance -Region $region.Region
    foreach ($rds in $RDSInstances)
    {
        $RDSObj = New-Object -TypeName System.Management.Automation.PSObject -Property ([ordered]@{
                'AvailabilityZone' = $rds.AvailabilityZone;
                'Engine' = $rds.Engine;
                'EngineVersion' = $rds.EngineVersion;
                'StorageType' = $rds.StorageType;
                'AllocatedStorage' = $rds.AllocatedStorage;
                'DBInstanceIdentifier' = $rds.DBInstanceIdentifier;
                'DBName' = $rds.DBName;
                'MasterUsername' = $rds.MasterUsername;
                'InstanceCreateTime' = $rds.InstanceCreateTime;
                'MultiAZ' = $rds.MultiAZ;
                'Region' = $region.Name;
            })
        $RDSArray += $RDSObj
    }


}
$RDSArray | Export-csv -Path .\HG-RDS.csv -NoTypeInformation
$out | Export-Csv -Path .\HG-EC2.csv -NoTypeInformation

