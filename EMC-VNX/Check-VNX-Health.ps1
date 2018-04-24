# Query the SAN for health of physical disks, requires Navisphere CLI.
# Jonathan Fox
# Tested against a EMC VNX 5300, should work for all VNX1 range devices.

Param( 
    [parameter()][string] $HostAddress, 
    [parameter()][string] $Username,
    [parameter()][string] $Password
) 


# Query the SAN for current disk status
$Query = & "C:\Program Files (x86)\EMC\Navisphere CLI\NaviSECCli.exe" ""-h $HostAddress -User $Username -Password $Password -Scope 0 getdisk -state""

# Calculate the total number of disks
$TotalDisks = (Select-String -InputObject $Query -Pattern "disk" -AllMatches).Matches.Count

# Calculate the total number of Hot Spares
$HotSpares = (Select-String -InputObject $Query -Pattern "hot" -AllMatches).Matches.Count

# Calculate the number of disks in notable states
$RebuildingDisks = (Select-String -InputObject $Query -Pattern "rebuilding|equalizing" -AllMatches).Matches.Count
$FailedDisks = (Select-String -InputObject $Query -Pattern "failed|faulted|fault" -AllMatches).Matches.Count

#PRTG service condition
write-host "<prtg>"
write-host "<result>"
write-host "<channel>Total Disks</channel>"
write-host "<customunit>Disk(s)</customunit>"
write-host "<value>$TotalDisks</value>"
write-host "</result>"

write-host "<result>"
write-host "<channel>Hot Spare Disks</channel>"
write-host "<customunit>Disk(s)</customunit>"
write-host "<value>$HotSpares</value>"
write-host "</result>"

If ($RebuildingDisks -gt 0) {
    write-host "<result>"
    write-host "<channel>Rebuilding Disks</channel>"
    write-host "<customunit>Disk(s)</customunit>"
    write-host "<value>$RebuildingDisks</value>"
    write-host "<warning>1</warning>"
    write-host "</result>`n"
} ElseIf ($RebuildingDisks -eq 0) {
    write-host "<result>"
    write-host "<channel>Rebuilding Disks</channel>"
    write-host "<customunit>Disk(s)</customunit>"
    write-host "<value>0</value>"
    write-host "</result>"
}

If ($FailedDisks -gt 0) {
    write-host "<result>"
    write-host "<channel>Failed Disks</channel>"
    write-host "<customunit>Disk(s)</customunit>"
    write-host "<value>$FailedDisks</value>"
    write-host "</result>"
} ElseIf ($FailedDisks -eq 0) {
    write-host "<result>"
    write-host "<channel>Failed Disks</channel>"
    write-host "<customunit>Disk(s)</customunit>"
    write-host "<value>0</value>"
    write-host "</result>"
}

#PRTG message display
If ($FailedDisks -eq 0 -and $RebuildingDisks -eq 0) {
    write-host "<text>All Disks OK</text>"
} ElseIf ($FailedDisks -eq 0 -and $RebuildingDisks -gt 0) {
    write-host "<text>WARNING $RebuildingDisks disk(s) rebuilding or equalizing</text>"
} ElseIf ($FailedDisks -gt 0) {
    write-host "<text>FAILURE $FailedDisks disk(s) failed</text>"
    write-host "<error>1</error>"
}

write-host "</prtg>"