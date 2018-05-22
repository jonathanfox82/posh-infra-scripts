# Simple script to reformat the phone numbers to a new format

#List users

Get-ADUser -SearchBase "OU=Domain,DC=ghfinancials,DC=co,DC=uk" `
-Filter 'enabled -eq $true' `
-Properties SamAccountName,telephoneNumber, mobile  | Where-Object { $_.telephoneNumber -match '\(\+44\) 0' } | Select DisplayName,telephoneNumber, @{Name="FormattedNumber"; Expression =  {($_.telephoneNumber).Replace("(+44) 0","+44 ")}} | ft


# Set the phone numbers
Get-ADUser -SearchBase "OU=Domain,DC=ghfinancials,DC=co,DC=uk" `
-Filter 'enabled -eq $true' `
-Properties SamAccountName,telephoneNumber, mobile | Where-Object { $_.telephoneNumber -match '\(\+44\) 0' } | % { Set-ADUser -Identity $_.SamAccountName -OfficePhone ($_.telephoneNumber).Replace("(+44) 0","+44 ")}

