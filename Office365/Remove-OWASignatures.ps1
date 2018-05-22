$LiveCred = Get-Credential
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell/ -Credential $LiveCred -Authentication Basic -AllowRedirection

Import-PSSession $Session

$mailboxes = Get-Mailbox -ResultSize unlimited
$mailboxes | foreach { Set-MailboxMessageConfiguration -identity $_.alias -SignatureHtml "" }


