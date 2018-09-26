[string]$global:baseURL = "https://apigateway.trade.tt"
[string]$global:CacheFile = ".\instruments.xml"

# This function creates the keys as strings.
function ConvertPSObjectToHashtable
{
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    process
    {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string])
        {
            $collection = @(
                foreach ($object in $InputObject) { ConvertPSObjectToHashtable $object }
            )

            Write-Output -NoEnumerate $collection
        }
        elseif ($InputObject -is [psobject])
        {
            $hash = @{}

            foreach ($property in $InputObject.PSObject.Properties)
            {
                $hash[$property.Name] = ConvertPSObjectToHashtable $property.Value
            }

            $hash
        }
        else
        {
            $InputObject
        }
    }
}

function Get-TimeStamp {
    
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
    
}

<# 
    This function sets the API vars to use to communicate with the REST API.
    There are 2 ways to set API vars, through command line or through environment variables.
    If API vars have been specified from the command line, they override vars from environment.
#>
function Test-APIVars {
    [CmdletBinding()]
    Param
    (
        # TT API Key
        [string]$ParamKey,
        # TT API Key Secret
        [string]$ParamSecret
    )
    ### Checking parms are correctly set ###
    # Param set from command line overrides environment variables
    if ($ParamKey) {
        Write-Host "$(Get-TimeStamp) API Key passed as parameter."
        $global:APIKey = $ParamKey
    }
    else {
        if ((Test-Path env:TT_RESTAPI_KEY)) {
            $global:APIKey = $env:TT_RESTAPI_KEY
            Write-Host "$(Get-TimeStamp) API Key found from Environment Variable"
        }
        else {
            Write-Host "$(Get-TimeStamp) No TT REST API Key set, exiting"
            Write-Host "$(Get-TimeStamp) Specify an API Key using the -APIKey param or as an Environment variable called TT_RESTAPI_KEY"
            Exit
        }
    }
    if ($ParamSecret) {
        Write-Host "$(Get-TimeStamp) APISecret passed as parameter."
        $global:APISecret = $ParamSecret
    }
    else {
        if ((Test-Path env:TT_RESTAPI_SECRET)) {
            $global:APISecret = $env:TT_RESTAPI_SECRET
        Write-Host "$(Get-TimeStamp) API Secret found from Environment Variable"
        }
        else {
            Write-Host "$(Get-TimeStamp) No TT REST API Secret set, exiting"
            Write-Host "$(Get-TimeStamp) Specify an API Secret using the -APISecret param or as an Environment variable called TT_RESTAPI_SECRET"
            Exit
        }
    }
}

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
        # TT Environment
        [Parameter(mandatory=$true)]
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
        Write-Host "$(Get-TimeStamp) Error getting Access token, check API Key and API secret"
        Write-Host "$(Get-TimeStamp) Using"
        Write-Host "$(Get-TimeStamp) API Key: $APIKey"
        Write-Host "$(Get-TimeStamp) API Secret: $APISecret"
        Write-Host "$(Get-TimeStamp) Environment: $Environment"
        Write-Host "$(Get-TimeStamp) StatusCode:" $_.Exception.Response.StatusCode.value__ 
        Write-Host "$(Get-TimeStamp) StatusDescription:" $_.Exception.Response.StatusDescription
        Exit
    }

    # Set the global variable access_token so it can be used in all modules.
    $global:APIToken = $AccessToken.access_token

    # format HTTP header for data GET requests
    $global:DataRequestHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $DataRequestHeaders.Add("x-api-key", $APIKey)
    $DataRequestHeaders.Add("Authorization", 'Bearer '+ $APIToken )
}

<#
.Synopsis
   Get the list of accounts on TT
.DESCRIPTION
   Connect to the TT REST API and get a full list of the TT accounts associated with the API key specified
   Returns only the data from the request (not the status)
   https://library.tradingtechnologies.com/tt-rest/risk.html
.EXAMPLE
   Get-TTMarkets -Environment ext-prod-live
#>
function Get-TTAccounts
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment
    )

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
        if ($nextPageKey) {
            $RESTRequest = "$baseURL/risk/$Environment/accounts?nextPageKey=$nextPageKey"
        }
        else {
            $RESTRequest = "$baseURL/risk/$Environment/accounts"
        }
        $AccountsResponse = Get-TTRestResponse -Request $RESTRequest
        $nextPageKey = $AccountsResponse.nextPageKey
        $Accounts += $AccountsResponse.accounts   
        $i++
    }
    until ($AccountsResponse.lastPage -eq $true)

    # Return array of accounts
    Return $Accounts
}

<#
Gets a list of risk and limit parameters associated with the specified accountId and a list of all users,
along with their respective user account permissions, linked to the accountId.
https://library.tradingtechnologies.com/tt-rest/risk.html

#>
function Get-TTAccountInfo {
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment,
        # Account ID
        [Parameter(mandatory=$true)]
        [string]$AccountID
    )

    $RESTRequest = "$baseURL/risk/$Environment/account/$AccountID"

    $AccountInfoResponse = Get-TTRestResponse -Request $RESTRequest

    if ($AccountInfoResponse.status -eq 'ok') {
        $AccountInfo = $AccountInfoResponse.account
        Return $AccountInfo
    }

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
        [Parameter(mandatory=$true)]
        [PSObject[]]$Objects
    )
    # Create a hashtable for markets
    $HashTable = @{}

    Foreach ($object in $Objects) {
        Write-Debug $object.name
        $HashTable.add([int]$object.id, $object.name)
    }
    Return $HashTable
}

function Convert-HashtableToObjectArray {
    [CmdletBinding()]
    Param
    (
        [Parameter(mandatory=$true)]
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
   Return a hashtable with cached instrument data if it exists
.DESCRIPTION
   Look for a local file and import the existing cache if it exists,
   Otherwise return an empty hashtable object
.EXAMPLE
   Get-InstrumentCache -CacheFilePath custom.xml
#>
function Get-InstrumentCache {
    Param
    (
        [Parameter(mandatory=$true)]
        [string]$CacheFilePath
    )
    # Create a hashtable for instruments.
    $instrumentsCache= @{}

    if (Test-Path -Path $CacheFile) {
        $instrumentsCache = Import-Clixml -Path $CacheFilePath
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
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment,
        # Array of instrumentsIds to add to cache
        [Parameter(mandatory=$true)]
        [uint64[]]$InstrumentIDs
    )

    # Obtain a REST response for markets
    $MarketsRESTResponse = Get-TTMarkets -Environment $Environment
    # Convert markets object to a hashtable
    $MarketsHashTable = Convert-TTRESTObjectToHashtable -Objects $MarketsRESTResponse

    # Get existing cached data
    $instCache = Get-InstrumentCache -CacheFilePath $CacheFile

    Foreach ($instrumentId in $InstrumentIDs) {

        # If the instrument is in cache already just use that data.
        if ($instCache.ContainsKey($instrumentId)) {
            # Do Nothing
        }
        else {
            # Obtain the new instrument data from TT REST API as it is not stored in the XML cache
            Write-Host "$(Get-TimeStamp) Obtain the instrument data for $instrumentId from the TT REST API"

            $instRequestResponse = ""
            $RESTRequest = "$baseURL/pds/$Environment/instrument/$instrumentId"
            $instRequestResponse =  Get-TTRestResponse -Request  $RESTRequest

            # if this works, lookup market name using market ID and market hash table and add to this object
            $marketID = $instRequestResponse.instrument.marketid
            $marketName = $MarketsHashTable[$marketID]
            $instRequestResponse.instrument | Add-Member -type NoteProperty -Name "Market" -Value $marketName

            Write-Host "$(Get-TimeStamp) ======== NEW INSTRUMENT DATA ========"
            Write-Host Name: $instRequestResponse.instrument.name 
            Write-Host Alias: $instRequestResponse.instrument.alias
            
            # Now add this instrument to the instruments cache object
            $instCache.add($instrumentId, $instRequestResponse.instrument )
        }

    }

    # Export new copy of cached instrument data overwriting old file.
    $instCache | Export-Clixml -Path $CacheFile

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
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment,
        # Account IDs to filter on
        [string]$AccountFilter,
        [string[]]$IncludeMarket,
        [string[]]$ExcludeMarket
    )

    # Obtain a REST response for accounts
    $AccountsRESTResponse = Get-TTAccounts -Environment $Environment

    # Convert result to a hashtable
    $AccountsHashTable = Convert-TTRESTObjectToHashtable -Objects $AccountsRESTResponse

    # Get the positions from Positions function
    $Positions = Get-TTPositions -Environment $Environment `
                                 -AccountIDs $AccountFilter

    # Get the list of unique instruments in the positions response to use to lookup the instrument data for.
    # This instrument data is required to determine the marketId. alias and symbol later.
    [uint64[]]$uniqueInstruments= @()
    $uniqueInstruments = $Positions | Select-Object instrumentID -Unique -ExpandProperty instrumentID

    # Populate the instrument cache with the unique instruments.
    # We are only really interested in the market and product/alias names so these are safe to cache as they don't change.
    $InstrumentCache = Add-InstrumentDataToCache -Environment $Environment `
                                                 -InstrumentIDs $uniqueInstruments

    # Enrich information for each position entry in the positions object
    # Add the Account name, Market, Product Symbol and instrument alias.
    # Filter by market if that is specified.
    $Positions | % {

        # Lookup instrument data using instrument ID and instruments hash table
        $instId = $_.instrumentId

        $ExpiryDate = [datetime]::parseexact($InstrumentCache[[uint64]$instId].expirationDate.ToString().SubString(0,8), 'yyyyMMdd',$null)

        $_ | Add-Member -type NoteProperty -Name "Market" -Value $InstrumentCache[[uint64]$instId].Market
        $_ | Add-Member -type NoteProperty -Name "Contract" -Value $InstrumentCache[[uint64]$instId].alias
        $_ | Add-Member -type NoteProperty -Name "Product" -Value $InstrumentCache[[uint64]$instId].productSymbol
        $_ | Add-Member -type NoteProperty -Name "ExpirationDate" -Value $ExpiryDate
        $_ | Add-Member -type NoteProperty -Name "TickValue" -Value $InstrumentCache[[uint64]$instId].tickValue
        $_ | Add-Member -type NoteProperty -Name "TickSize" -Value $InstrumentCache[[uint64]$instId].tickSize
        $_ | Add-Member -type NoteProperty -Name "PointValue" -Value $InstrumentCache[[uint64]$instId].pointValue

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

function Convert-EpochNanoToDate {
    Param
    (  
        # TT API Key
        [int64]$EpochTime
    )
    $origin = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0

    if ($EpochTime) {
        # For nanosecond calc, divide nano seconds by 1000000000 to get seconds then add those seconds to 1 Jan 1970 00:00:00
        Return ($origin.AddSeconds(([math]::Round($EpochTime / 1000000000))))
    }
    else {
        Return $null
    }

}

function Get-TTProducts
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment,
        # Market
        [Parameter(mandatory=$true)]
        [string]$MarketId
    )

    $RESTRequest = "$baseURL/pds/$Environment/products?marketId=$MarketId"

    $ProductsResponse = Get-TTRestResponse -Request $RESTRequest
    
    $Products = $ProductsResponse.products

    $Products | % { $_ | Add-Member -NotePropertyName marketId -NotePropertyValue $MarketId }
    Return $Products

}

function Get-TTProductDetail
{
    [CmdletBinding()]
    Param
    (
        [Parameter(mandatory=$true)]
        [string]$Environment,
        [Parameter(mandatory=$true)]
        [string]$ProductId
    )
    $RESTRequest = "$baseURL/pds/$Environment/product/$ProductId"

    $ProductDetailResponse = Get-TTRestResponse -Request $RESTRequest
    
    $ProductDetail = $ProductDetailResponse.product

    Return $ProductDetail
}

<#
.Synopsis
   Get the TT Positions from the monitor API
.DESCRIPTION
   Gets positions based on today’s fills for all accounts associated with the application key or for specific accounts.
   Included in the response are SODs.
.EXAMPLE
   Get-TTPositions -Environment ext-prod-live -AccountIDs 10200
#>
function Get-TTPositions
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment,
        [string]$AccountIDs
    )
    # If a filter is specified append that to the REST request
    # Use ScaleQty 0 to get the total number of contracts rather than contracts in flow for energy products
    if ($AccountIDs)
    {
        $RESTRequest = "$baseURL/monitor/$Environment/position?accountIds=$AccountIDs&scaleQty=0"
    }
    else
    {
        $RESTRequest = "$baseURL/monitor/$Environment/position?scaleQty=0"
    }

    $PositionsResponse = Get-TTRestResponse -Request $RESTRequest
    
    $Positions = $PositionsResponse.positions

    Return $Positions
}
function Get-TTFills
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment,
        [string]$minTimestamp,
        [string]$maxTimestamp
    )
    $FillsArray=@()
    $maxTimeStampDate = Convert-EpochNanoToDate($maxTimestamp)
    do
    {
    # What are we requesting ?
        $minTimeStampDate = Convert-EpochNanoToDate($minTimestamp)
        Write-Host Request: $minTimeStampDate to $maxTimeStampDate

        $Fills = ""

        $RESTRequest = "$baseURL/ledger/$Environment/fills?minTimestamp=$minTimestamp&maxTimestamp=$maxTimestamp"

        $FillsResponse = Get-TTRestResponse -Request $RESTRequest
    
        $Fills = $FillsResponse.fills

        # Add to array
        $FillsArray += $Fills

        # Calculate new window to query if there are more results to obtain
        if ($fills.Count -ne 0) {
            $minTimestamp = ($fills | select -Last 1 | select timestamp).timestamp
            $minTimeStampDate = $origin.AddSeconds(([math]::Round($minTimestamp / 1000000000)))
        }
    }
    until ($fills.Count -le 1)

    Return $FillsArray
}

function Get-TTOrders
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment,
        # comma separated set of account Ids
        [Parameter(mandatory=$false)]
        [string]$AccountIDs
    )
    # If a filter is specified append that to the REST request
    if ($AccountIDs)
    {
        $RESTRequest = "$baseURL/ledger/$Environment/orders?accounts=$AccountIDs"
    }
    else
    {
        $RESTRequest = "$baseURL/ledger/$Environment/orders"
    }

    $OrdersResponse = Get-TTRestResponse -Request $RESTRequest
    
    $Orders = $OrdersResponse.orders

    Return $Orders
}
function Get-TTPositionModifications
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment,
        # Present the records with newest timestamps first. (0 = no, 1 = yes)
        [string]$Reverse,
        # Maximum number of records to include in the response.
        [string]$Count,
        # Filter response to position modifications on a specific account. Account ID can be retrieved using the Risk service’s /accounts GET request.
        [string]$AccountIDs,
        # Filters response to position modifications before a specific time. Entered as epoch time in nanoseconds.
        [string]$MaxTimestamp,
        # Filters response to position modifications after a specific time. Entered as epoch time in nanoseconds.
        [string]$MinTimestamp
    )
    # Not yet implemented
}

# Safely get data from TT REST API
function Get-TTRestResponse {
    [CmdletBinding()]
    Param
    (
        [string]$Request
    )
    $retryCount = 0
    Write-Host Request: $Request
    do {
        try {
            $response = ""
            $response = Invoke-RestMethod -Uri $Request -Method Get -Headers $DataRequestHeaders
        } 
        catch {
            Write-Host "$(Get-TimeStamp) Error looking up data"
            Write-Host "$(Get-TimeStamp) StatusCode:" $_.Exception.Response.StatusCode
            Write-Host "$(Get-TimeStamp) StatusDescription:" $_.Exception.Response.StatusDescription
            Start-Sleep 0.5
        }
        Write-Host "$(Get-TimeStamp) Response: $($response.status)"
        $retryCount++;

        if ($retryCount -gt 10) {
            Write-Host "$(Get-TimeStamp) Error looking up data $retryCount times, quitting"
            Exit
        }
    }
    until ($response.status -eq "Ok")

    Return $response
}

<#
   Gets a list of supported country IDs, codes, names that you can
   use when adding a user with the /user endpoint.
#>
function Get-TTCountryIds
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment
    )
    $RESTRequest = "$baseURL/risk/$Environment/user/countryIds"

    $CountryIdsResponse = Get-TTRestResponse -Request $RESTRequest
    
    $CountryIds = $CountryIdsResponse.countries

    Return $CountryIds
}
<#
   Gets a list of supported country IDs, codes, names that you can
   use when adding a user with the /user endpoint.
#>
function Get-TTStateIds
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment
    )
    $RESTRequest = "$baseURL/risk/$Environment/user/stateIds"

    $StateIdsResponse = Get-TTRestResponse -Request $RESTRequest
    
    $StateIds = $StateIdsResponse.states

    Return $StateIds
}
<#
   Gets a list of supported country IDs, codes, names that you can
   use when adding a user with the /user endpoint.
#>
function Get-TTUsers
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment
    )

    # Get remaining user data until we have all the user data
    $nextPageKey = ""
    $i=0
    $users=@()

    do  {
        # Failsafe
        If($i -gt 20) {break}

        Start-Sleep 0.5
        if ($nextPageKey) {
            $RESTRequest = "$baseURL/risk/$Environment/users?nextPageKey=$nextPageKey"
        }
        else {
            $RESTRequest = "$baseURL/risk/$Environment/users"
        }
        $UsersResponse = Get-TTRestResponse -Request $RESTRequest
        $nextPageKey = $UsersResponse.nextPageKey
        Write-Host "Got $($UsersResponse.users.count) more users"
        $Users += $UsersResponse.users   
        $i++
    }
    until ($UsersResponse.lastPage -eq $true)
    
    Write-host total of $Users.count user accounts obtained
    Return $Users
}


# PDS Section (Reference Data)
function Get-TTInstrumentRefData
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment
    )
    $RESTRequest = "$baseURL/pds/$Environment/instrumentdata"

    $InstrumentDataResponse = Get-TTRestResponse -Request $RESTRequest
    
    Return $InstrumentDataResponse
}


<#
.Synopsis
   Get a TT Markets REST Response
.DESCRIPTION
   Connect to the TT REST API and get a list of the TT markets.
   Returns only the data from the request (not the status)
.EXAMPLE
   Get-TTMarkets -Environment ext-prod-live
#>
function Get-TTMarkets
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment
    )
    $RESTRequest = "$baseURL/pds/$Environment/markets"

    $MarketsResponse = Get-TTRestResponse -Request $RESTRequest
    
    $Markets = $MarketsResponse.markets

    Return $Markets
}

<#
Gets a list of Market Identification Codes (MIC).
#>
function Get-TTMICs
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment
    )
    $RESTRequest = "$baseURL/pds/$Environment/mics"

    $MICsResponse = Get-TTRestResponse -Request $RESTRequest
    
    $MICs = $MICsResponse.markets

    Return $MICs
}

function Get-TTProductTypes
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment
    )
    $RESTRequest = "$baseURL/pds/$Environment/productdata"

    $ProductTypesResponse = Get-TTRestResponse -Request $RESTRequest
    
    $ProductTypes = $ProductTypesResponse.productTypes

    Return $ProductTypes

}
<#
    Gets details about a product family and lists products within that family.
#>
function Get-TTProductsInFamily
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment,
        # Product Family ID. Can be retrieved by the Get-TTProducts function
        [Parameter(mandatory=$true)]
        $ProductFamilyId
    )
    $RESTRequest = "$baseURL/pds/$Environment/productfamily?productFamilyId=$ProductFamilyId"

    $ProductFamilyResponse = Get-TTRestResponse -Request $RESTRequest
    
    $ProductFamily = $ProductFamilyResponse.productFamily

    Return $ProductFamily

}

<#
    Gets details about a product family.
#>
function Get-TTProductFamilyDetails
{
    [CmdletBinding()]
    Param
    (
        # TT Environment
        [Parameter(mandatory=$true)]
        [string]$Environment,
        # Product Family ID. Can be retrieved by the Get-TTProducts function
        [Parameter(mandatory=$true)]
        $ProductFamilyId
    )

    $RESTRequest = "$baseURL/pds/$Environment/productfamily/$ProductFamilyId"

    $ProductFamilyDetailsResponse = Get-TTRestResponse -Request $RESTRequest
    
    $ProductFamilyDetails = $ProductFamilyDetailsResponse.productFamily

    Return $ProductFamilyDetails

}
