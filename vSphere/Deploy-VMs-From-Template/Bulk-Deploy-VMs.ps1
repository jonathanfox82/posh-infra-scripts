Param(
    [Parameter(Mandatory=$True)]
    [string]$vCenter,   
    [Parameter(Mandatory=$True)]
    [string]$vmCsv
)
#############################################################
# Syntax and sample for CSV File:
# template,datastore,diskformat,vmhost,custspec,vmname,ipaddress,subnet,gateway,pdns,sdns,datacenter,folder,stdpg,memsize,cpucount
# template.2008ent64R2sp1,DS1,thick,host1.domain.com,2008r2CustSpec,Guest1,10.50.35.10,255.255.255.0,10.50.35.1,10.10.0.50,10.10.0.51,DCName,FldrNm,stdpg.10.APP1,2048,1
#
$vmlist = Import-CSV $vmCsv

# Load PowerCLI
$psSnapInName = "VMware.VimAutomation.Core"
if (-not (Get-PSSnapin -Name $psSnapInName -ErrorAction SilentlyContinue))
{
# Exit if the PowerCLI snapin cannot be loaded
Add-PSSnapin -Name $psSnapInName -ErrorAction Stop
}
Connect-VIServer $vCenter
foreach ($item in $vmlist) {

# Map variables
$datastore = $item.datastore
$diskformat = $item.diskformat
$custspec = $item.custspec
$vmname = $item.vmname
$ipaddr = $item.ipaddress
$subnet = $item.subnet
$gateway = $item.gateway
$pdns = $item.pdns
$sdns = $item.sdns
$datacenter = $item.datacenter
$template = Get-Datacenter -Name $datacenter | Get-Template -Name $item.template
$destfolder = Get-Datacenter -Name $datacenter | Get-Folder -Name $item.folder
$vmhost = $item.vmhost
$stdpg = $item.stdpg
$memsize = $item.memsize
$cpucount = $item.cpucount
$description = $item.description
$VMExists = Get-VM -Name $vmname -ErrorAction SilentlyContinue

if (!$VMExists) {
Write-Host "No VM named $vmname exists"
# Configure the Customization Spec info if static IP is defined
Get-OSCustomizationSpec $custspec | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping -IpMode UseStaticIp -IpAddress $ipaddr -SubnetMask $subnet -DefaultGateway $gateway #-Dns $pdns
# Deploy the VM based on the template with the adjusted Customization Specification
New-VM -Name $vmname -Template $template -Datastore $datastore -DiskStorageFormat $diskformat -VMHost $vmhost -Description $description | Set-VM -OSCustomizationSpec $custspec -Confirm:$false
# Move VM to Applications folder
Get-vm -Name $vmname | move-vm -Destination $destfolder
# Set the Port Group Network Name (Match PortGroup names with the VLAN name)
Get-VM -Name $vmname | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $stdpg -Confirm:$false
# Set the number of CPUs and MB of RAM
Get-VM -Name $vmname | Set-VM -MemoryMB $memsize -NumCpu $cpucount -Confirm:$false
# Start the VM
Start-VM -VM $vmname
}
else
{
Write-Host "A VM named $vmname already exists"
}

}
Disconnect-VIServer $vCenter -Confirm:$false