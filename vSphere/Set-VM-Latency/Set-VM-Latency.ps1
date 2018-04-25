<#
.Synopsis
   Set specific VMs latency sensivity to a custom value.
.DESCRIPTION
   Set specific VMs latency sensivity to a custom value. Select using a name pattern supplied as a parameter called $NameSpec.
.EXAMPLE
   Set all VMs back to normal latency sensitivity
   Set-VM-Latency.ps1 -vCenter myVcenter.domain.local
.EXAMPLE
   Set VMs matching *edge* to High latency sensitivity.
   Set-VM-Latency.ps1 -vCenter myVcenter.domain.local -NameSpec "*edge*" -Sensitivity High
 .VERSION 1.0
#>

Param(
  [Parameter(Mandatory=$True)]
  [string]$vCenter,
  [Parameter(Mandatory=$True)]
  [string]$NameSpec="*",
  [Parameter(Mandatory=$True)]
  [string]$Sensitivity="normal"
)


# Import PowerCLI Modules 
Write-Host Importing VMware Modules
Get-Module -ListAvailable VM* | Import-Module

# Connect to vCenter
Write-Host Connecting to vCenter server $vCenter
Connect-ViServer -server $vCenter -ErrorAction Stop | Out-Null

# Valid Sensitivity Values
$sensitivityValues = "low","medium","normal","high"

if ($sensitivityValues -contains $Sensitivity)
{

    Get-VM -Name $NameSpec | Get-View | foreach {
        $ConfigSpec = New-Object VMware.Vim.VirtualMachineConfigSpec
        $OValue = New-Object VMware.Vim.optionvalue
        $OValue.Key = "sched.cpu.latencySensitivity"
        $OValue.Value = $Sensitivity
        $ConfigSpec.extraconfig += $OValue

        # Also reserve all guest memory if this is set to high.
        if ($Sensitivity -eq "high") { $ConfigSpec.memoryReservationLockedToMax = $true }
        # Remove reservation if latency it set to a different value
        if ($Sensitivity -ne "high") { $ConfigSpec.memoryReservationLockedToMax = $false }

        # Reconfigure the VM
        $task = $_.ReconfigVM_Task($ConfigSpec)
        Write "$($_.Name) – changed"

}
    }


}
else {
    Write-Host Invalid sensitivity setting selected.
    Exit
}
