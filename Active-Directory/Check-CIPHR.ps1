
# Obtain list of AD users from domain with blank employeeIDs
$results = Get-ADUser -SearchBase "OU=Domain,DC=ghfinancials,DC=co,DC=uk" `
-Filter 'enabled -eq $true' `
-Properties employeeID, DisplayName,Office,Department,title,mail `
| Where-Object {$_.employeeID -eq $null} `
| Select-Object DisplayName,Office,Department,title,mail

if ($results.Count -gt 0) {
    Write-Host "Found $($results.Count) Records"

    $header =@"
The following Active Directory users have missing employeeIDs, this means they will not sync with CIPHR

Please add the CIPHR IDs to the Active Directory attribute employeeID.

The CIPHR ID should come from an email sent to it.london@ghfinancials.com from CIPHR directly when the new user was added.

Please ask HR to supply the CIPHR IDs if you cannot find the email from the CIPHR system.
"@

    $body = $results | Out-String
        
    $content = $header + $body

    Write-Host "Sending email notification"
    Send-MailMessage -To "it.london@ghfinancials.com" -From "server.engineering@ghfinancials.com" -Subject "AD Users CIPHR Check" -SmtpServer "smtp.ghfinancials.co.uk" -Body $content
}
