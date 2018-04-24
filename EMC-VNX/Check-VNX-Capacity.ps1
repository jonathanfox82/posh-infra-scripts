# Query the SAN for storage pool 0 capacity, requires Navisphere CLI.
# Jonathan Fox
# Tested against a EMC VNX 5300, should work for all VNX1 range devices.

Param( 
    [parameter()][string] $HostAddress, 
    [parameter()][string] $Username,
    [parameter()][string] $Password
) 
# Define warning/error levels.
$upperErrorLevel = 90
$upperWarningLevel = 70

$Query = & "C:\Program Files (x86)\EMC\Navisphere CLI\NaviSECCli.exe" ""-h $HostAddress -User $Username -Password $Password -Scope 0 storagepool -list -id 0 -prcntFull"" | Out-String

$Query = $Query.Trim()
$percentFull = $Query.Substring($Query.Length - 7,7)

$intvalue = $percentFull -as[int]

write-host "<prtg>"
write-host "<result>"
write-host "<channel>Percent Full</channel>"
write-host "<customunit>%</customunit>"
write-host "<value>$intvalue</value>"
write-host "</result>"
#PRTG message display



If ($intvalue -gt $upperErrorLevel) {
    write-host "<text>Storage Pool Usage Critical</text>"
    write-host "<error>1</error>"
} ElseIf ($intvalue -gt $upperWarningLevel ) {
    write-host "<text>WARNING Storage Pool Usage High</text>"
    write-host "<warning>1</warning>"
} Else {
    write-host "<text>All OK</text>"
}

write-host "</prtg>"