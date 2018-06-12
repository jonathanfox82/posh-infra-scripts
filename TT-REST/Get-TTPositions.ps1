<#
.Synopsis
   Get the overall P/L net position from TT NET accounts.
.DESCRIPTION
   Connect to the TT REST API and download the positions, this can be filtered by optional Accounts or Markets
   http://library.tradingtechnologies.com/tt-rest/gs-getting_started_with_tt-rest.html
   Alerts if a values is above a certain threshold.
.EXAMPLE
   Get-TT-NetPos.ps1 -APIkey <API Key> -APISecret <API Secret> -Environment "ext_prod_live"
   Supply your own API key and connect to live environment
.EXAMPLE
   Get-TT-NetPos.ps1 -APIkey <API Key> -APISecret <API Secret> -Environment "ext_prod_live"
   Get positions and email results.
.EXAMPLE
   Get-TT-NetPos.ps1 -APIkey <API Key> -APISecret <API Secret> -Environment "ext_prod_live" `
                     -Email "riskmc@ghfinancials.com" -Accounts "XGAAL","XGDAB" -Markets "ICE","LIFFE"
   Get positions only for 2 specified accounts and 2 specified markets. Email the results to riskmc@ghfinancials.com
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

    # Account names to filter as comma separated list.
    [Parameter(mandatory=$false)]
    [string[]]$Accounts,

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
$smtpServer = "smtp.ghfinancials.co.uk"
$fromAddress = "newttpositions@ghfinancials.com"
$subject = "TT Position Alert"
####################################################

$dataobj = (Get-Date)

<# 
 INITIAL SETUP AND OBTAIN TT API TOKEN, CHECK PARAMS ARE VALID
#>

$global:APIKey = ""
$global:APISecret = ""

Test-APIVars -ParamKey $TTAPIKey -ParamSecret $TTAPISecret

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

# Check if the account param is defined, if so then check it's a valid selection against the accounts REST response hashtable.
if ($Accounts) {
    $AccountIDFilter = @()

    foreach ($account in $Accounts) {
        if ($AccountsHashTable.values -notcontains $account) {
            Write-Host Invalid account parameter specified, exiting
            Write-Host Valid options are 
            Write-Host $AccountsHashTable.Values
            Write-Host 'Specify accounts as a comma separated list of strings e.g. -Accounts "XGAAL","MERCURY"'
            Exit
        }
        else {
        
        }
        # Create an array of AccountIDs to pass to the positions REST API
        $AccountIDFilter += $AccountsHashTable.GetEnumerator() | Where-Object { $_.Value -eq $account }
    }
}

# Format the accounts filter array to be a comma separated list for the REST request later
[string]$AccountIDFilterString = $AccountIDFilter.Name -join ","

# Get the positions
Write-Host Get Positions -ForegroundColor Black -BackgroundColor Cyan
$EnrichedPositions = Get-EnrichedPositionData -APIKey $APIKey `
                                              -APIToken $APIToken `
                                              -Environment $Environment `
                                              -AccountFilter $AccountIDFilterString `
                                              -IncludeMarket $IncludeMarkets `
                                              -ExcludeMarket $ExcludeMarkets

<# 
 CALCULATIONS
#>
# initialise PNL Table Array
$PNLTable = @()

# If an accounts parameter is specified then show a PNL table filtered by account.
if ($Accounts) {
    # Get Positions grouped by Account and Market
    $GroupedPositions = $EnrichedPositions | Select AccountName, Market, pnl | Group-Object -Property AccountName, Market

    $PNLTable += foreach($item in $GroupedPositions) {

        $item.Group | Select -Unique AccountName, Market,
        @{Name = 'PnL';Expression = {(($item.Group) | measure -Property pnl -sum).Sum}}
    }
    # Print PNL Table
    $PNLTable | Select AccountName, Market, @{N='PnL'; E={"{0:c}" -f $_.PnL}}  | Format-Table | Out-String| % {Write-Host $_}

}
# Otherwise just show an overall PnL by Exchange
else {
    # Select Positions and group by market, add each entry to the PNLTable array
    $EnrichedPositions | Group-Object -Property Market | % { 
        $PNLEntry = New-Object psobject -Property @{
            Market = $_.Name
            PnL = ($_.Group | Measure-Object pnl -Sum).Sum
        }
    $PNLTable += $PNLEntry
    }

    # Print PNL Table
    $PNLTable | Select Market, @{N='PnL'; E={"{0:c}" -f $_.PnL}}  | Format-Table | Out-String| % {Write-Host $_}
}

# Sum total PNL
$TotalPNL = "{0:c}" -f ($PNLTable | Measure-Object PnL -Sum).Sum
# Print total PNL
Write-Host Total PNL: $TotalPNL

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

$body = $PNLTable | Sort-Object PnL | Select Exchange, @{N='PnL'; E={[math]::Round($_.PnL,2)}} | Out-String
$msg.Body = @"

AccountsFilter: $($accounts)

TT Positions from REST API at  $($dataobj.ToString('yyyy/MM/dd HH:mm:ss'))

$($body.ToString())

"@

$smtp.Send($msg)
}


