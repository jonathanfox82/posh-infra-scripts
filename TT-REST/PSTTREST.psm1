[string]$baseURL = "https://apigateway.trade.tt"

<#
.Synopsis
   Connect to the TT REST API and obtain a token
.DESCRIPTION
.EXAMPLE
   Get-TTRESTToken -APIkey "myapikey" -APISecret "myapisecret" -Environment "ext_prod_live"
   Supply your own API key and connect to live environment
#>
function Get-TTRESTToken
{
    [CmdletBinding()]
    Param
    (
        # TT API Key
        [string]$APIKey,
        # TT API Key Secret part
        [string]$APISecret,
        # TT Environment
        [string]$Environment
    )

    # To get a token, you send your application key and application secret within a POST request to generate a token.
    # format HTTP header for token POST request
    $GetTokenHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $GetTokenHeaders.Add("x-api-key",$APIKey)
    $GetTokenHeaders.Add("Content-Type",'application/x-www-form-urlencoded')

    # Create body for token POST request
    $body = @{
        grant_type="user_app"
        app_key=$APISecret
    }

    # Get an API token using Invoke-RestMethod
    try {
        $AccessToken = Invoke-RestMethod -Uri $baseURL/ttid/$Environment/token -Method Post -Body $body -Headers $GetTokenHeaders -ContentType 'application/json'
    } 
    catch {
        Write-Host "Error getting Access token, check API Key and API secret"
        Write-Host "Using"
        Write-Host "API Key: $APIKey"
        Write-Host "API Secret: $APISecret"
        Write-Host "Environment: $Environment"
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ 
        Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
        Exit
    }

    # Return just the token
    Return $AccessToken.access_token
}

<#
.Synopsis
   Get the list of accounts on TT
.DESCRIPTION
   Connect to the TT REST API and get a full list of the TT accounts associated with the API key specified
   Returns only the data from the request (not the status)
.EXAMPLE
   Get-TTMarkets -APIKey <API Key> -APIToken <API Token> -Environment ext-prod-live
#>
function Get-TTAccounts
{
    [CmdletBinding()]
    Param
    (
        # TT API Key
        [string]$APIKey,
        # TT API Token
        [string]$APIToken,
        # TT Environment
        [string]$Environment
    )

    # format HTTP header for data GET requests
    $DataRequestHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $DataRequestHeaders.Add("x-api-key", $APIKey)
    $DataRequestHeaders.Add("Authorization", 'Bearer '+ $APIToken )

    # Get remaining accounts data until we have all the account data
    # The TT REST API does something odd here and returns duplicate accounts details, I filter those
    # out later on with a Select -unique statement.
    $nextPageKey = ""
    $i=0
    $accounts=@()
    do  {
        # Failsafe
        If($i -gt 20) {break}

        Start-Sleep 0.5
        $response = Invoke-RestMethod -Uri $baseURL/risk/$Environment/accounts?nextPageKey=$nextPageKey -Method Get -Headers $DataRequestHeaders
        $nextPageKey = $response.nextPageKey
        $accounts += $response.accounts   
        $i++
    }
    until ($response.lastPage -eq $true)

    # Return array of accounts
    Return $accounts
}

<#
.Synopsis
   Get a TT Markets REST Response
.DESCRIPTION
   Connect to the TT REST API and get a list of the TT markets.
   Returns only the data from the request (not the status)
.EXAMPLE
   Get-TTMarkets -APIKey <API Key> -APIToken <API Token> -Environment ext-prod-live
#>
function Get-TTMarkets
{
    [CmdletBinding()]
    Param
    (
        # TT API Key
        [string]$APIKey,
        # TT API Token
        [string]$APIToken,
        # TT Environment (default to UAT)
        [string]$Environment
    )
    # format HTTP header for data GET requests
    $DataRequestHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $DataRequestHeaders.Add("x-api-key", $APIKey)
    $DataRequestHeaders.Add("Authorization", 'Bearer '+ $APIToken )
    
    # Get markets data 
    $markets = Invoke-RestMethod -Uri $baseURL/pds/$Environment/markets -Method Get -Headers $DataRequestHeaders

    Return $markets.markets
}

<#
.Synopsis
   Takes the reference data REST request that contain an id and a name and converts it to a hash table.
.DESCRIPTION
   Takes the reference data REST request that contain an id and a name and converts it to a hash table.
.EXAMPLE
   Convert-TTRESTObjectToHashtable -Object <Markets REST Response object>
#>

function Convert-TTRESTObjectToHashtable {
    [CmdletBinding()]
    Param
    (
        [PSObject[]]$Objects
    )
    # Create a hashtable for markets
    $HashTable = @{}

    Foreach ($object in $Objects) {
        $HashTable.add([int]$object.id, $object.name)
    }
    Return $HashTable
}

function Convert-HashtableToObjectArray {
    [CmdletBinding()]
    Param
    (
        [hashtable]$HashTable
    )
    # Create an array for output
    $Array = @()
    foreach ($h in $HashTable.GetEnumerator()) {
        $Array += $($h.Value)
    }
    Return $Array
}


<#
.Synopsis
   Get the TT Positions from the monitor API
.DESCRIPTION
   Connect to the TT REST API, obtain the positions and return only the data from the request (not the status)
.EXAMPLE
   Get-TTPositions -APIKey <API Key> -APIToken <API Token> -Environment ext-prod-live
#>
function Get-TTPositions
{
    [CmdletBinding()]
    Param
    (
        # TT API Key
        [string]$APIKey,
        # TT API Token
        [string]$APIToken,
        # TT Environment
        [string]$Environment,
        [string]$AccountFilter
    )

    # format HTTP header for data GET requests
    $DataRequestHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $DataRequestHeaders.Add("x-api-key", $APIKey)
    $DataRequestHeaders.Add("Authorization", 'Bearer '+ $APIToken )

    $retrycount=1
    $maxRetries=10 # Try 10 times

    # If a filter is specified append that to the REST request
    # Use ScaleQty 0 to get the total number of contracts rather than contracts in flow for energy products
    if ($AccountFilter) {
        $RESTRequest = "$baseURL/monitor/$Environment/position?accountIds=$AccountFilter&scaleQty=0"
    }
    else {
        $RESTRequest = "$baseURL/monitor/$Environment/position?scaleQty=0"
    }
    do {
        try {
        $retrycount++
        $response = ""
        $response = Invoke-RestMethod -Uri $RESTRequest -Method Get -Headers $DataRequestHeaders
        } catch {
            # Catch any errors such as Too Many Requests, throttle rate limit and try again until Status is Ok.
            Write-Host "Error looking up position data $RESTRequest"
            Write-Host "Using"
            Write-Host "API Key: $APIKey"
            Write-Host "Environment: $Environment"
            Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ 
            Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
            Start-Sleep 0.2
        }
    }
    until (($response.status -eq "Ok") -Or ($retrycount -gt $maxRetries))

    # If the data requests failed up to the max number retries, then exit.
    if ($retrycount -gt $maxRetries) {
        Write-Host "Maximum retries exceeded when obtaining position data"
        Exit
    }

    # Create new positions array containing only the position data from the REST response (not the status messages)
    $positions = @()
    $positions = $response.positions
    Return $positions
}

<#
.Synopsis
   Return a hashtable with cached instrument data if it exists
.DESCRIPTION
   Look for a local file and import the existing cache if it exists,
   Otherwise return an empty hashtable object
.EXAMPLE
   Get-InstrumentCache -Path custom.xml
#>
function Get-InstrumentCache {
    [CmdletBinding()]
    Param
    (
        # Path
        [string]$Path = 'Data\instruments.xml'
    )
    # format HTTP header for data GET requests
    $DataRequestHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $DataRequestHeaders.Add("x-api-key", $APIKey)
    $DataRequestHeaders.Add("Authorization", 'Bearer '+ $APIToken )

    # Create a hashtable for instruments.
    $instrumentsCache= @{}

    if (Test-Path -Path $Path) {
        $instrumentsCache = Import-Clixml -Path $Path
    }
    Return $instrumentsCache
}

<#
.Synopsis
   Add Instrument Data to the Instrument cache
.DESCRIPTION
   Given a list of Instrument IDs, populate an existing XML cache with instrument data.
.EXAMPLE
   Add-InstrumentDataToCache -InstrumentIDs 213123123123,123123123123 -CacheFile 'custom.xml'
#>
function Add-InstrumentDataToCache {
    [CmdletBinding()]
    Param
    (  
        # TT API Key
        [string]$APIKey,
        # TT API Token
        [string]$APIToken,
        # TT Environment
        [string]$Environment,
        # Array of instrumentsIds to add to cache
        [uint64[]]$InstrumentIDs,
        [string]$CacheFile
    )
    # format HTTP header for data GET requests
    $DataRequestHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $DataRequestHeaders.Add("x-api-key", $APIKey)
    $DataRequestHeaders.Add("Authorization", 'Bearer '+ $APIToken )

    # Obtain a REST response for markets
    $MarketsRESTResponse = Get-TTMarkets -APIKey $APIKey -APIToken $APIToken -Environment $Environment
    # Convert markets object to a hashtable
    $MarketsHashTable = Convert-TTRESTObjectToHashtable -Objects $MarketsRESTResponse

    # Get existing cached data
    $instCache = Get-InstrumentCache -Path $CacheFile

    Foreach ($instrumentId in $InstrumentIDs) {

        # If the instrument is in cache already just use that data.
        if ($instCache.ContainsKey($instrumentId)) {
            # Do Nothing
        }
        else {
            # Obtain the new instrument data from TT REST API as it is not stored in the XML cache
            Write-Host "Obtain the instrument data for $instrumentId from the TT REST API"
            do {
                try {
                    $instRequestResponse = ""
                    $instRequestResponse = Invoke-RestMethod -Uri $baseURL/pds/$Environment/instrument/$instrumentId -Method Get -Headers $DataRequestHeaders 
                } catch {
                    # Catch any errors such as Too Many Requests, throttle rate limit and try again until Status is Ok.#
                    Write-Host "Error looking up Instrument data for $instrumentId"
                    Write-Host "Using"
                    Write-Host "API Key: $APIKey"
                    Write-Host "Environment: $Environment"
                    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ 
                    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
                    Start-Sleep 0.2
                }
            }
            until ($instRequestResponse.status -eq "Ok")

            # if this works, lookup market name using market ID and market hash table and add to this object
            $marketID = $instRequestResponse.instrument.marketid
            $marketName = $MarketsHashTable[$marketID]
            $instRequestResponse.instrument | Add-Member -type NoteProperty -Name "Market" -Value $marketName

            Write-Host "======== NEW INSTRUMENT DATA ========"
            Write-Host Name: $instRequestResponse.instrument.name 
            Write-Host Alias: $instRequestResponse.instrument.alias
            Write-Host Market: $instRequestResponse.instrument.alias
            Write-Host "====================================="
            
            # Now add this instrument to the instruments cache object
            $instCache.add($instrumentId, $instRequestResponse.instrument )
        }

    }

    # Export new copy of cached instrument data overwriting old file.
    $instCache | Export-Clixml -Path 'Data\instruments.xml'

    Return $instCache
}

<#
.Synopsis
   Combine data from multiple TT REST calls to get full position data
.DESCRIPTION
   Call the accounts TT REST API and the Instruments function.
   Get the positions and match the instrument IDs, add extra fields for Market, Alias and Symbol
   Add the AccountName based on the accountId field matched against the Accounts REST API
#>
function Get-EnrichedPositionData {
    [CmdletBinding()]
    Param
    (  
        # TT API Key
        [string]$APIKey,
        # TT API Token
        [string]$APIToken,
        # TT Environment
        [string]$Environment,
        # Account IDs to filter on
        [string]$AccountFilter,
        [string[]]$IncludeMarket,
        [string[]]$ExcludeMarket
    )
    # Obtain a REST response for accounts
    Write-Host Call Get-TTAccounts function from Get-EnrichedPositionData function
    Write-Host Using APIKey $APIKey APIToken $APIToken  Environment $Environment
    $AccountsRESTResponse = Get-TTAccounts -APIKey $APIKey `
                                           -APIToken $APIToken `
                                           -Environment $Environment

    Write-Host Call Convert-TTRESTObjectToHashtable function from Get-EnrichedPositionData function
    # Convert result to a hashtable
    $AccountsHashTable = Convert-TTRESTObjectToHashtable -Objects $AccountsRESTResponse

    # Get the positions from Positions function
    $Positions = Get-TTPositions -APIKey $APIKey `
                                 -APIToken $APIToken `
                                 -Environment $Environment `
                                 -AccountFilter $AccountFilter

    # Get the list of unique instruments in the positions response to use to lookup the instrument data for.
    # This instrument data is required to determine the marketId. alias and symbol later.
    [uint64[]]$uniqueInstruments= @()
    $uniqueInstruments = $Positions | Select-Object instrumentID -Unique -ExpandProperty instrumentID

    # Populate the instrument cache with the unique instruments.
    # We are only really interested in the market and product/alias names so these are safe to cache as they don't change.
    $InstrumentCache = Add-InstrumentDataToCache -APIKey $APIKey `
                                                 -APIToken $APIToken `
                                                 -Environment $Environment `
                                                 -InstrumentIDs $uniqueInstruments `
                                                 -CacheFile $InstCacheFile

    # Enrich information for each position entry in the positions object
    # Add the Account name, Market, Product Symbol and instrument alias.
    # Filter by market if that is specified.
    $Positions | % {

        # Lookup instrument data using instrument ID and instruments hash table
        $instId = $_.instrumentId
        $_ | Add-Member -type NoteProperty -Name "Market" -Value $InstrumentCache[[uint64]$instId].Market
        $_ | Add-Member -type NoteProperty -Name "Contract" -Value $InstrumentCache[[uint64]$instId].alias
        $_ | Add-Member -type NoteProperty -Name "Product" -Value $InstrumentCache[[uint64]$instId].productSymbol

        # Lookup account name using account ID and accounts hash table
        $accountID = $_.accountID
        if ($AccountsHashTable.ContainsKey($accountID)) {
            $_ | Add-Member -type NoteProperty -Name "AccountName" -Value $AccountsHashTable[$accountID]
        }
        else {
            # This should never happen but just in case the accounts request had a problem or was incomplete, output an error to console
            Write-Host Account $accountID not found in lookup table -ForegroundColor Black -BackgroundColor Red
            $missingAccounts += $accountID
        }
    }
    <# 
     FILTER POSITIONS
    #>
    # If IncludeMarket is set then filter to only that market
    If ($IncludeMarket) {
        $Positions = $Positions | Where-Object {  $IncludeMarket -contains $_.Market }
    }
    # If ExcludeMarket is set then filter out that market.
    If ($ExcludeMarket) {
        $Positions = $Positions | Where-Object {  $ExcludeMarket -notcontains $_.Market }
    }

    Return $Positions

}