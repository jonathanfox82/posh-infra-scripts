param 
( 
    [parameter()][string] $FolderPath,
    [parameter()][string] $ArchivePath    
)

$arr = @()
$timestamp = Get-Date -Format o | foreach {$_ -replace ":", "."}
$ReportDir = "c:\temp"

Get-ChildItem "$FolderPath" |  % {
  $obj = New-Object PSObject
  $obj | Add-Member NoteProperty Path $_.FullName
  $obj | Add-Member NoteProperty Directory $_.DirectoryName
  $obj | Add-Member NoteProperty Name $_.Name
  $obj | Add-Member NoteProperty Length $_.Length
  $obj | Add-Member NoteProperty Owner ((Get-ACL $_.FullName).Owner)

      if ($obj.Owner -like "*S-1-5*") {
        $arr += $obj
        Write-Host "Moving $obj.Path to $ArchivePath"
        Move-Item -Path $obj.Path -Destination $ArchivePath
      }
  }
  $arr | Export-CSV -notypeinformation "$ReportDir\$timestamp report.csv"

  