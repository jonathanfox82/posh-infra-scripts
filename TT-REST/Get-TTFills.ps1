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

# Import from Recs folder copy. 
Import-Module '\\ghfinancials.co.uk\GHF\Projects\Automations\TTREST-Scripts\PSTTREST.psm1' -ErrorAction Stop

################ VARIABLES BLOCK ###################
$baseURL = "https://apigateway.trade.tt"
$smtpServer = "smtp.ghfinancials.co.uk"
$fromAddress = "ttfills@ghfinancials.com"
$subject = "TT Fills Report"
[datetime]$origin = '1970-01-01 00:00:00'
$date = (Get-Date).ToString('yyyyMMdd-HHmmss')
$logfile = "Logs\$date.log"
####################################################

$global:APIKey = ""
$global:APISecret = ""

Test-APIVars -ParamKey $TTAPIKey -ParamSecret $TTAPISecret

# Get Midnight for maxtimeStamp
$maxTimestamp=[int64]((Get-Date -Hour 0 -Minute 00 -Second 00)-(get-date "1/1/1970")).TotalMilliseconds * 1000000

$d = Get-Date -Hour 0 -Minute 00 -Second 00
if ('Monday' -contains $d.DayOfWeek) {
  $prevWD = $d.AddDays(-3)
}
 elseif ('Sunday' -contains $d.DayOfWeek) {
  $prevWD = $d.AddDays(-2)
} else {
  $prevWD = $d.AddDays(-1)
}

# Set Output file name

$filename = $($prevWD.ToString('yyyyMMdd'))

# Get Midnight for minTimeStamp

<#
 INITIAL SETUP AND OBTAIN TT API TOKEN, CHECK PARAMS ARE VALID
#>

# Get an API token using module, this function sets the value of $APIToken globally.
Get-TTRESTToken -Environment $Environment

# Obtain a REST response for accounts
$AccountsRESTResponse = Get-TTAccounts -Environment $Environment

# Convert result to a hashtable
$AccountsHashTable = Convert-TTRESTObjectToHashtable -Objects $AccountsRESTResponse

# Obtain a REST response for markets
$MarketsRESTResponse = Get-TTMarkets -Environment $Environment

# Convert markets object to a hashtable
$MarketsHashTable = Convert-TTRESTObjectToHashtable -Objects $MarketsRESTResponse

# Check if the market param is defined, if so then check it's a valid selection against the markets REST response hashtable.
if ($IncludeMarkets) {
    $MarketIDFilter = @()

    foreach ($market in $IncludeMarkets) {
        if ($MarketsHashTable.values -notcontains $market) {
            Write-Host "$(Get-TimeStamp) Invalid markets parameter specified, exiting"
            Write-Host Valid options are 
            Write-Host $MarketsHashTable.Values
            Write-Host 'Specify markets as a comma separated list of strings e.g. -Markets "ICE","LIFFE"'
            Exit
        }
        $MarketIDFilter += $MarketsHashTable.GetEnumerator() | Where-Object { $_.Value -eq $market }
    }
}

$OrderDataResponse = Invoke-RestMethod -Uri $baseURL/ledger/$Environment/orderdata -Method Get -Headers $DataRequestHeaders
$OrderData = ConvertPSObjectToHashtable -InputObject $OrderDataResponse.orderData

$StartProcessingTime = Get-Date

$FillsArray=@()
$maxTimeStampDate = Convert-EpochNanoToDate($maxTimestamp)

do
{
    # What are we requesting ?
    $minTimeStampDate = Convert-EpochNanoToDate($minTimestamp)
    $RESTRequest = "$baseURL/ledger/$Environment/fills?minTimestamp=$minTimestamp&maxTimestamp=$maxTimestamp"

    # Invoke request
    $retryCount=0
    do {
        try {
            Write-Host "$(Get-TimeStamp) Requesting: $minTimeStampDate to $maxTimeStampDate"
            $fillsResponse = ""
            $RequestTime = Measure-Command { $fillsResponse = Invoke-RestMethod -Uri $RESTRequest -Method Get -Headers $DataRequestHeaders}
        } catch {
            # Catch any errors such as Too Many Requests, throttle rate limit and try again until Status is Ok.
            Write-Host "$(Get-TimeStamp) Error looking up fills"
            Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ 
            Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
            $retryCount++;
            Start-Sleep 0.2

            if ($retryCount -gt 10) { 
                Write-Host "$(Get-TimeStamp) Exceeded maximum retries, exiting."
                Exit
            }

        }
    }
    until ($fillsResponse.status -eq "Ok")
          
    $fills = $fillsResponse.fills  # | Select -Property account, accountId, avgPx, brokerId, cumQty, currUserId, deltaQty, execInst, execType, externallyCreated, instrumentId, lastPx, lastQty, manualOrderIndicator, marketId, multiLegReportingType, orderId, recordId, securityDesc, senderLocationId, senderSubId, side, source, syntheticType, timeStamp, tradeDate, transactTime

    Write-Host "$(Get-TimeStamp) Downloaded $($fills.Count) new fills in $($RequestTime.Seconds) seconds"
  
    # Add to array
    $FillsArray += $fills
   

    # Calculate new window to query if there are more results to obtain
    if ($fills.Count -ne 0) {
        [uint64]$lastRecordTimeStamp = (($fills | select -Last 1 | select timestamp).timestamp)
        [uint64]$minTimestamp = $lastRecordTimeStamp + 1
        $minTimeStampDate = $origin.AddSeconds(([math]::Round($minTimestamp / 1000000000)))
    }
}
until ($fills.Count -le 1)

$EndProcessingTime = Get-Date
$ProcessingTime = New-TimeSpan –Start $StartProcessingTime -End $EndProcessingTime

Write-Host "$(Get-TimeStamp) Total Fills Downloaded: $($FillsArray.Count) in $($ProcessingTime.Seconds) seconds"

Write-Host "$(Get-TimeStamp) Converting data to readable format (could take some time)."
$FormattedFills = $FillsArray | Select `
                                account,`
                                avgPx,`
                                brokerId,`
                                cumQty,`
                                currUserId,`
                                deltaQty,`
                                execInst,`
                                @{N='executionType';E={$OrderData.executionType[$($_.execType).toString()]}},`
                                externallyCreated,`
                                instrumentId,`
                                lastPx,`
                                lastQty,`
                                manualOrderIndicator,
                                @{N='Market';E={$MarketsHashtable[$_.marketId]}} ,`
                                multiLegReportingType,` # Need to convert this to readable format
                                orderId,`
                                recordId,`
                                securityDesc,`
                                senderLocationId,`
                                senderSubId,`
                                @{N='side';E= {$OrderData.side[$($_.side).toString()]}},`
                                source,` # Need to convert this to readable format
                                @{N='synthType';E={$OrderData.syntheticType[$($_.syntheticType).toString()]}},`
                                @{N='timeStamp';E={$(Convert-EpochNanoToDate -EpochTime $_.timeStamp)}},`
                                @{N='tradeDate';E={$(Convert-EpochNanoToDate -EpochTime $_.tradeDate)}}, `
                                @{N='transactTime';E={$(Convert-EpochNanoToDate -EpochTime $_.transactTime)}}

#Import-DataToDatabaseTable -DBServer lonix-sql04 -DBName RiskDB -TblName Staging_TTFills -DataObject $FillsArray

Write-Host "$(Get-TimeStamp) Exporting to CSV"

# Export RAW copy
$FillsArray | Export-CSV -Path "\\ghfinancials.co.uk\GHF\Projects\Automations\Recs-GetTTFills\Data\ext_prod_live\$($date)-fills-raw.csv" -NoTypeInformation
# Export Formatted copy
$FormattedFills | Export-CSV -Path "\\ghfinancials.co.uk\GHF\Projects\Automations\Recs-GetTTFills\Data\ext_prod_live\$($date)-formatted.csv" -NoTypeInformation