Param(
    [Parameter(mandatory=$true)]
    [Int]$expireDays,

    [String]$logFile="F:\Logs\VNX-Snaps.Log",

    [Parameter(mandatory=$true)]
    [Array]$targetLuns,

    [Parameter(mandatory=$true)]
    [Array]$sanArray
)

Write-Host "Working with snapshot expiration time of $((Get-Date).AddDays(-$expireDays).addHours(-1))"

Foreach ($connectionParams in $sanArray) {
    $Temp = Connect-EmcSystem -SystemType VNX-Block -CreationParameters $connectionParams
}

$allLuns = Get-EmcLun

#Get Target EMC LUNs
$targetEmcLuns = @()
foreach ($targetLun in $targetLuns) {
    if ($allLuns | ? {$_.Name -eq $targetLun}) {
        Write-Host "Got LUN: $($targetLun)"
        $targetEmcLuns += $allLuns | ? {$_.Name -eq $targetLun}
    } else {
        Write-Warning "Target LUN $($targetLun) does not exist on any connected storage system"
    }
}
Write-Host "Got $($targetEmcLuns.Count) LUNs"

#Discover SnapView snapshots older than $expireDays and delete them
$expiredSnaps = $targetEmcLuns | 
    % {Get-EmcSnapshotLun -SourceLun $_} | 
    ? {$_.Name -match "^autoSnap-" } |
    ? {$_.CreationTime -lt (Get-Date).AddDays(-$expireDays).AddHours(-1) }

    Write-Host "Got $($expiredSnaps.Count) expired snapview snapshots"

foreach ($expiredSnap in $expiredSnaps) {
    Write-Host "Remove expired snapshot $($expiredSnap.Name)"
    $Remo = Remove-EmcSnapshotLun -SnapshotLun $expiredSnap -Force
}

# Discover Advanced snapshots older than $expireDays and delete them

# Has to use the name field since EMC PowerShell doesn't populate creation time
$expiredAdvancedSnaps = $targetEmcLuns | 
    % { Get-EmcVnxAdvancedSnapshot -SourceLun $_ } | 
    ? {$_.Name -match "^autoSnap-" } |
    ? {[DateTime]($_.Name -split '-',3)[-1] -lt `
        (Get-Date).AddDays(-$expireDays).AddHours(-1) }

Write-Host "Got $($expiredAdvancedSnaps.Count) expired advanced snapshots"

foreach ($expiredAdvancedSnap in $expiredAdvancedSnaps) {
    Write-Host "Remove expired snapshot $($expiredAdvancedSnap.Name)"
    $Remo = Remove-EmcVnxAdvancedSnapshot -AdvancedSnapshot $expiredAdvancedSnap -Force
}

#Create new snaps for each of the target LUNs
foreach ($targetEmcLun in $targetEmcLuns) {
    if ($targetEmcLun.OtherProperties.PoolLun) {
        $snapName = "autoSnap-$($targetEmcLun.Name)-$(Get-Date -Format o)"
        Write-Host "Snap LUN $($targetEmcLun.Name) (Advanced), Snap Name: $($snapName)"  
        $Create = New-EmcVnxAdvancedSnapshot -SourceLun $targetEmcLun `
            -Name $snapName `
            -AllowReadWrite $false -AllowAutoDelete $true
    } else {
        $snapName = "autoSnap-$($targetEmcLun.Name)-$(Get-Date -Format o)"
        Write-Host "Snap LUN $($targetEmcLun.Name) (SnapView), Snap Name: $($snapName)"
        $Create = New-EmcSnapshotLun -SourceLun $targetEmcLun `
            -Name $snapName `
            -Retention (New-TimeSpan -Days $expireDays)
    }
}