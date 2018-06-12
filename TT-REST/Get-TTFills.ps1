


<#
.Synopsis
   Obtain an extract of the fills for Recs team for yesterdays fills
.DESCRIPTION
   Connect to the TT REST API and download the fills, this can be filtered by optional Accounts or Markets
   http://library.tradingtechnologies.com/tt-rest/gs-getting_started_with_tt-rest.html
.EXAMPLE
   Get-TTFills.ps1 -APIkey <API Key> -APISecret <API Secret> -Environment "ext_prod_live"
   Supply your own API key and connect to live environment
.EXAMPLE
   Get-TTFills.ps1 -APIkey <API Key> -APISecret <API Secret> -Environment "ext_prod_live"
   Get fills and email results.
.EXAMPLE
   Get-TTFills.ps1 -APIkey <API Key> -APISecret <API Secret> -Environment "ext_prod_live" `
                     -Email "riskmc@ghfinancials.com" -Accounts "XGAAL","XGDAB" -Markets "ICE","LIFFE"
   Get fills only for 2 specified accounts and 2 specified markets. Email the results to riskmc@ghfinancials.com
#>
Param
(
    # TT API Key
    [Parameter(mandatory=$false)]
    [string]$TTAPIKey,

    # TT API Key Secret part
    [Parameter(mandatory=$false)]
    [string]$TTAPISecret,

    # TT Environment (default live)
    [Parameter(mandatory=$false)]
    [string]$global:Environment = "ext_prod_live",

    # Market name to include as string array
    [Parameter(mandatory=$false)]
    [string[]]$IncludeMarkets,

    # Email address to send a notification to (only supports one address)
    [Parameter(mandatory=$false)]
    [string]$Email
)

Write-Host Importing TTREST Module

# Remove module if it exists already
Remove-Module PSTTREST -ErrorAction SilentlyContinue

# Import Module 
Import-Module '.\PSTTREST.psm1' -ErrorAction Stop

################ VARIABLES BLOCK ###################
$baseURL = "https://apigateway.trade.tt"
$smtpServer = "smtp.ghfinancials.co.uk"
$fromAddress = "ttfills@ghfinancials.com"
$subject = "TT Fills Report"
[datetime]$origin = '1970-01-01 00:00:00'
$date = (Get-Date).ToString('yyyyMMdd-HHmmss')
####################################################

$global:APIKey = ""
$global:APISecret = ""

Test-APIVars -ParamKey $TTAPIKey -ParamSecret $TTAPISecret

# Get Midnight for current date
$maxTimestamp=[int64]((Get-Date -Hour 0 -Minute 00 -Second 00)-(get-date "1/1/1970")).TotalMilliseconds * 1000000
# Get Midnight for yesterday
$minTimestamp=[int64]((Get-Date -Hour 0 -Minute 00 -Second 00).AddDays(-1)-(get-date "1/1/1970")).TotalMilliseconds * 1000000

# Get time now
#$maxTimestamp=[int64]((Get-Date)-(get-date "1/1/1970")).TotalMilliseconds * 1000000
# Get Midnight for current date
#$minTimestamp=[int64]((Get-Date -Hour 0 -Minute 00 -Second 00)-(get-date "1/1/1970")).TotalMilliseconds * 1000000

<#
 INITIAL SETUP AND OBTAIN TT API TOKEN, CHECK PARAMS ARE VALID
#>

# Get an API token using module, this function sets the value of $APIToken globally.
Get-TTRESTToken -APIKey $APIKey `
                -APISecret $APISecret `
                -Environment $Environment

# Obtain a REST response for accounts
$AccountsRESTResponse = Get-TTAccounts -APIKey $APIKey `
                                       -APIToken $APIToken `
                                       -Environment $Environment

# Convert result to a hashtable
$AccountsHashTable = Convert-TTRESTObjectToHashtable -Objects $AccountsRESTResponse

# Obtain a REST response for markets
$MarketsRESTResponse = Get-TTMarkets -APIKey $APIKey `
                                     -APIToken $APIToken `
                                     -Environment $Environment

# Convert markets object to a hashtable
$MarketsHashTable = Convert-TTRESTObjectToHashtable -Objects $MarketsRESTResponse

# Check if the market param is defined, if so then check it's a valid selection against the markets REST response hashtable.
if ($IncludeMarkets) {
    $MarketIDFilter = @()

    foreach ($market in $IncludeMarkets) {
        if ($MarketsHashTable.values -notcontains $market) {
            Write-Host Invalid markets parameter specified, exiting
            Write-Host Valid options are 
            Write-Host $MarketsHashTable.Values
            Write-Host 'Specify markets as a comma separated list of strings e.g. -Markets "ICE","LIFFE"'
            Exit
        }
        $MarketIDFilter += $MarketsHashTable.GetEnumerator() | Where-Object { $_.Value -eq $market }
    }
}

# format HTTP header for data GET requests
$DataRequestHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$DataRequestHeaders.Add("x-api-key", $APIKey)
$DataRequestHeaders.Add("Authorization", 'Bearer '+ $APIToken )


$OrderDataResponse = Invoke-RestMethod -Uri $baseURL/ledger/$Environment/orderdata -Method Get -Headers $DataRequestHeaders -ContentType 'application/json'
$OrderData = $OrderDataResponse.orderData


$StartProcessingTime = Get-Date

$FillsArray=@()
$maxTimeStampDate = Convert-EpochNanoToDate($maxTimestamp)
do
{
    # What are we requesting ?
    $minTimeStampDate = Convert-EpochNanoToDate($minTimestamp)
    #$RESTRequest = "$baseURL/ledger/$Environment/fills?accountId=52387&minTimestamp=$minTimestamp&maxTimestamp=$maxTimestamp"
    $RESTRequest = "$baseURL/ledger/$Environment/fills?minTimestamp=$minTimestamp&maxTimestamp=$maxTimestamp"

    # Invoke request
    do {
        try {
            Write-Host Request: $minTimeStampDate to $maxTimeStampDate
            $fillsResponse = ""
            $RequestTime = Measure-Command { $fillsResponse = Invoke-WebRequest -Uri $RESTRequest -Method Get -Headers $DataRequestHeaders -ContentType 'application/json'}
        } catch {
            # Catch any errors such as Too Many Requests, throttle rate limit and try again until Status is Ok.
            Write-Host "Error looking up fills"
            Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ 
            Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
        }
    }
    until ($fillsResponse.StatusCode -eq 200)
        
    $fillsResponse = $fillsResponse.ToString()
    # Crude hack to fix issue with TT API
    
    $fills = $fillsResponse.Replace("currUserId`": ,","currUserId`":`"`"`,") | ConvertFrom-Json

    Write-Host Downloaded $fills.fills.Count new fills in $RequestTime.Seconds seconds

    # Output results
    #$fills.fills | Format-Table | Out-String| % {Write-Host $_}
    
    # Add to array
    $FillsArray += $fills.fills

    # Calculate new window to query if there are more results to obtain
    if ($fills.fills.Count -ne 0) {
        $minTimestamp = ($fills.fills | select -Last 1 | select timestamp).timestamp
        $minTimeStampDate = $origin.AddSeconds(([math]::Round($minTimestamp / 1000000000)))
    }
}
until ($fills.fills.Count -le 1)


$EndProcessingTime = Get-Date
$ProcessingTime = New-TimeSpan –Start $StartProcessingTime -End $EndProcessingTime

Write-Host Total Fills Downloaded: $FillsArray.Count in 
Write-Host $ProcessingTime

$FillsArray | Export-Clixml -Path "Data\$Environment\$($date)-fills.xml" -Force

$FormattedFills = $FillsArray | Select @{N='DateandTime'; E={$(Convert-EpochNanoToDate -EpochTime $_.timeStamp)}}, account, @{N='Market'; E={$MarketsHashtable[$_.marketId]}}, @{N='Contract'; E={$_.securityDesc}}, deltaQty, lastQty
$FormattedFills | select -First 15 | ft


Exit

<# 
 EMAIL RESULTS
 If email address is defined, send to that address 
#>
If ($Email) {
Write-Host Sending email notifications

$msg = new-object Net.Mail.MailMessage
$smtp = new-object Net.Mail.SmtpClient($smtpServer)
$msg.From = $fromAddress
$msg.To.Add($Email)
$msg.Subject = $subject

$body = "CONTENT"
$msg.Body = @"

$($body.ToString())

"@

$smtp.Send($msg)
}


