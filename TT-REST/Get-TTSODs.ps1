<#
.Synopsis
   Get TT Start of Days from TT REST API for GHF Recs team.
.DESCRIPTION
   Connect to the TT API and download the TT SODs, then export to a CSV file under a subfolder called Data\<environment name>\
   Each file is timestamped with the days date.
   http://library.tradingtechnologies.com/tt-rest/gs-getting_started_with_tt-rest.html
.EXAMPLE
   Get-TTSODs.ps1
   Connects and uses the embedded API key in this script to connect to UAT
.EXAMPLE
   Get-TTSODs.ps1 -APIkey "myapikey" -APISecret "myapisecret" -Environment "ext_prod_live"
   Supply your own API key and connect to live environment
#>
Param
(
    # TT API Key
    [Parameter(mandatory=$true)]
    [string]$APIKey,

    # TT API Key Secret part
    [Parameter(mandatory=$true)]
    [string]$APISecret,

    # TT Environment (default live)
    [Parameter(mandatory=$false)]
    [string]$Environment = "ext_prod_live",

    # Market name to include as string array
    [Parameter(mandatory=$false)]
    [string[]]$IncludeMarkets,

    # Market name to exclude as string array
    [Parameter(mandatory=$false)]
    [string[]]$ExcludeMarkets,

    # Name of file to output (will also be timestamped)
    [string]$OutputFile = "REST-positions",

    # Email address to send a notification to (only supports one address)
    [Parameter(mandatory=$false)]
    [string]$Email
)
Write-Host Importing TTREST Module

# Remove module if it exists already
Remove-Module PSTTREST -ErrorAction SilentlyContinue

# Import from Recs folder copy. 
Import-Module '.\PSTTREST.psm1' -ErrorAction Stop

################ VARIABLES BLOCK ###################
$smtpServer = "smtp.ghfinancials.co.uk"
$fromAddress = "ttsodscript@ghfinancials.com"
$subject = "TT SOD Automation Completed"
$InstCacheFile = "Data\instruments.xml"
####################################################
$date = (Get-Date).ToString('yyyyMMdd-HHmmss')

<# 
 INITIAL SETUP AND OBTAIN TT API TOKEN, CHECK PARAMS ARE VALID
#>

# Create data folder for export
New-Item -ItemType Directory -Name Data\$Environment\ -ErrorAction SilentlyContinue

# Get an API token using module
$AccessToken = Get-TTRESTToken -APIKey $APIKey `
                               -APISecret $APISecret `
                               -Environment $Environment

# Get the positions
Write-Host Get Positions -ForegroundColor Black -BackgroundColor Cyan
$EnrichedPositions = Get-EnrichedPositionData -APIKey $APIKey `
                                              -APIToken $AccessToken `
                                              -Environment $Environment `
                                              -IncludeMarket $IncludeMarkets `
                                              -ExcludeMarket $ExcludeMarkets

# Generate Output Format (remove any SODs with quantity 0 as those are newly traded intraday positions)
$OutputFileName = "$($date)-$OutputFile.csv"
$Output = $EnrichedPositions | Where-Object { $_.sodNetPos -ne 0 } | Sort-Object AccountName,Market,Product,Contract | Select @{N='Account'; E={$_.AccountName}}, Market, Product, Contract,@{N='SOD Qty'; E={$_.sodNetPos}}

# Write to screen
$Output | Format-Table | Out-String| % {Write-Host $_}

# Export output to CSV.
Write-Host Exporting Positions -ForegroundColor Black -BackgroundColor Cyan
$Output | Export-Csv -Path ".\Data\$Environment\$OutputFileName" -NoTypeInformation

<# 
 EMAIL RESULTS
 If email address is defined, send to that address 
#>
If ($Email) {
Write-Host Sending email notifications
$file = "$(Get-Location)\Data\$Environment\$OutputFileName"
$att = new-object Net.Mail.Attachment($file)
$msg = new-object Net.Mail.MailMessage
$smtp = new-object Net.Mail.SmtpClient($smtpServer)
$msg.From = $fromAddress
$msg.To.Add($Email)
$msg.Subject = $subject

$msg.Body = @"
Completed downloading TT SODs for $date
Position Records: $($EnrichedPositions.count)
"@
$msg.Attachments.Add($att)
$smtp.Send($msg)
$att.Dispose()
}




