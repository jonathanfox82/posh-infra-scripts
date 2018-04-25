This script will bulk deploy Windows server from a Windows Server template on our vCenter. It will assign a static IP as well (doesn't support DHCP at the moment)

The Template should be copied to each remote location where appropriate so that at deployment time a local copy of the template is used to conserve WAN bandwidth.

The CSV format is self explanatory, important to enter the template

It should also work for Linux VMs but this has not been tested.