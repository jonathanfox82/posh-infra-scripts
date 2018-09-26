[string]$Environment = "ext_prod_live"
[string]$instCache = "Data\instruments.xml"
[string]$baseURL = "https://apigateway.trade.tt"

# Remove module if it exists already
Remove-Module PSTTREST -ErrorAction SilentlyContinue

# Import from Recs folder copy. 
Import-Module '.\PSTTREST.psm1' -ErrorAction Stop

Test-APIVars -ParamKey $APIKey -ParamSecret $APISecret

# Get an API token using module
$AccessToken = Get-TTRESTToken -Environment $Environment

# Obtain a REST response for accounts
$AccountsRESTResponse = Get-TTAccounts -Environment $Environment

# Obtain a REST response for markets
$MarketsRESTResponse = Get-TTMarkets -Environment $Environment

$EnrichedMercuryPositionData = Get-EnrichedPositionData -Environment $Environment -AccountFilter '40031'
$EnrichedPositionData = Get-EnrichedPositionData -Environment $Environment

$Today =  (Get-Date -Hour 00 -Minute 00 -Second 00)
$3Days = New-TimeSpan -Days 3
$EnrichedPositionData | Where-Object { $_.AccountName -match 'XG' -and $_.expirationdate -lt (Get-Date) + $3Days -and $_.netPosition -ne 0 } | Select AccountName, Market, Product, Contract, ExpirationDate, netPosition | Export-Csv .\LMERCURY_expiries.csv -NoTypeInformation
$EnrichedPositionData | Where-Object { $_.AccountName -match 'XG' -and $_.expirationdate -lt (Get-Date) + $3Days -and $_.netPosition -ne 0 } | Export-Csv .\expiries.csv -NoTypeInformation

# format HTTP header for data GET requests
$DataRequestHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$DataRequestHeaders.Add("x-api-key", $APIKey)
$DataRequestHeaders.Add("Authorization", 'Bearer '+ $APIToken )

$RESTRequest = "$baseURL/ledger/$Environment/fills"
$fills = Invoke-RestMethod -Uri $RESTRequest -Method Get -Headers $DataRequestHeaders -ContentType 'application/json'
Write-Host $fills.fills.Count

$OrderData = Invoke-RestMethod -Uri "$baseURL/ledger/$Environment/orderdata" -Method Get -Headers $DataRequestHeaders -ContentType 'application/json'

$PositionModifications = Invoke-RestMethod -Uri "$baseURL/ledger/$Environment/positionmodifications" -Method Get -Headers $DataRequestHeaders -ContentType 'application/json'

# Get Positions for LMERCURY
$positions = Invoke-RestMethod -Uri "$baseURL/monitor/$Environment/position?accountIds=40031&scaleQty=0" -Method Get -Headers $DataRequestHeaders -ContentType 'application/json'
$positions.positions |  ft



# Get Limit information
$MercuryAccounts = $AccountsRESTResponse  | Where-Object { $_.name -match 'XG' }

# Get top level information on the LMERCURY account
# $MercuryAccountInformation = Invoke-RestMethod -Uri "$baseURL/risk/$Environment/account/40031" -Method Get -Headers $DataRequestHeaders -ContentType 'application/json'

# Get information on the LMERCURY subaccounts account
$MercuryAccountInformation = @()
ForEach ($account in $MercuryAccounts) {
    Write-Host Getting data for $account.Name

    $AccountInformation = Invoke-RestMethod -Uri "$baseURL/risk/$Environment/account/$($account.id)" -Method Get -Headers $DataRequestHeaders -ContentType 'application/json'
    
    $MercuryAccountInformation  += $AccountInformation
    Start-Sleep 0.2
}

# Enrich product limits for export
# Get Reference Data
$ProductTypeData =  Invoke-RestMethod -Uri $baseURL/pds/$Environment/productdata -Method Get -Headers $DataRequestHeaders
$AccountsRESTResponse = Get-TTAccounts -Environment $Environment
$MarketsRESTResponse = Get-TTMarkets -Environment $Environment

# Get Limit information


# Select just the product limits
$ProductLimits = $MercuryAccountInformation.account.riskLimits.productLimits

# Select all the markets with product limits assigned.
$UniqueMarkets =  $ProductLimits.marketId | Select -Unique

$ProductCache = @()
# Get a list of products information for each of the above markets
Foreach ($mkt in $UniqueMarkets)
{
    $Products = Get-TTProducts -Environment $Environment -MarketId $mkt
    $ProductCache += $Products 
}
# END Product Ref Data caching


$ProductLimitArray = @()
# Cycle through each account

$MercuryAccountInformation.account | % { 

    $AccountID = $_.id

    # For each product limit.
    $_.riskLimits.productLimits | % {
        
        $ThisProductLimit = $_

        $MarketId = $_.marketId 
        $ProductId = $_.productId
        $ProductTypeId = $_.productTypeId

        Write-Host $AccountID
        Write-Host $MarketId
        Write-Host $ProductId
        Write-Host $ProductTypeId

        $Account = $AccountsRESTResponse | Where { $_.id -eq $AccountID }
        $Market = $MarketsRESTResponse | Where { $_.id -eq $MarketId }
        $Product = $ProductCache | Where { $_.id -eq $ProductId }
        $ProductType = $ProductTypeData.productTypes | Where { $_.id -eq $ProductTypeId }

        Write-Host $Account.name
        Write-Host $Market.name
        Write-Host $Product.name
        Write-Host $ProductType.name

        Start-Sleep 1
    
        $ThisProductLimit | Add-Member -type NoteProperty -Name "Account" -Value $Account.name -Force
        $ThisProductLimit | Add-Member -type NoteProperty -Name "Market" -Value $Market.name -Force
        $ThisProductLimit | Add-Member -type NoteProperty -Name "Product" -Value $Product.name -Force
        $ThisProductLimit | Add-Member -type NoteProperty -Name "ProductType" -Value -$ProductType.name -Force

        $ThisProductLimit += $ProductLimitArray
    }

}

$ProductLimitArray | Export-Csv -Notypeinformation .\limits.csv


# Export full account data to Json
$MercuryAccountInformation | ConvertTo-Json -Depth 6 | Out-File .\MercuryAccounts.json

$InstrumentData = Invoke-RestMethod -Uri $baseURL/pds/$Environment/instrumentdata -Method Get -Headers $DataRequestHeaders

$Instruments = Get-InstrumentCache -CacheFilePath $instCache
$MICs = Invoke-RestMethod -Uri $baseURL/pds/$Environment/mics -Method Get -Headers $DataRequestHeaders

$ICEProducts =  Invoke-RestMethod -Uri $baseURL/pds/$Environment/products?marketId=32 -Method Get -Headers $DataRequestHeaders
$ICELProducts = Invoke-RestMethod -Uri $baseURL/pds/$Environment/products?marketId=92 -Method Get -Headers $DataRequestHeaders

$ICEProducts.products | Where-Object { $_.symbol -match "GWM" } 

$GWM = $ICEProducts.products | Where-Object { $_.symbol -match "GWM" } 

$InstrumentDetails =  Invoke-RestMethod -Uri $baseURL/pds/$Environment/instrument/17745152642112576331 -Method Get -Headers $DataRequestHeaders

$InstrumentDetails.instrument
$InstrumentDetails.instrument.expirationDate 

$ProductFamily = Invoke-RestMethod -Uri $baseURL/pds/$Environment/productfamily?productFamilyId=4588915732259126548 -Method Get -Headers $DataRequestHeaders
$ProductFamilyDetails = Invoke-RestMethod -Uri $baseURL/pds/$Environment/productfamily/4588915732259126548 -Method Get -Headers $DataRequestHeaders

$UniqueInstruments = $positions | Select instrumentId -Unique -ExpandProperty instrumentID

$Instruments = Add-InstrumentDataToCache -APIKey $APIKey -APIToken $AccessToken -Environment $Environment -InstrumentIDs $UniqueInstruments -CacheFile $instCache

$JoinedPositions2 = $JoinedPositions | `
    Join-Object -LeftJoinProperty instrumentId -Right $AccountsRESTResponse `
                -RightJoinProperty id -RightProperties name `
                -Prefix Account `
                -Type AllInLeft

# initialise PNL Table Array
$PNLTable = @()

# Select Positions and group by market, add each entry to the PNLTable array
$positions | Group-Object -Property Market | % { 
    $PNLEntry = New-Object psobject -Property @{
        Account = $_.AccountName
        Exchange = $_.Name
        PnL = ($_.Group | Measure-Object pnl -Sum).Sum
    }
    $PNLTable += $PNLEntry
}
$PNLTable = @()
$PNLTable  = $positions | Select AccountName, Market, Product, pnl | Group-Object AccountName, Market

$PNLTable | % {
    $PNLEntry = New-Object psobject -Property @{
        Group = $_.Name
        PnL = ($_.Group | Measure-Object pnl -Sum).Sum
    }
    $PNLTable += $PNLEntry
}



# Obtain a REST response for accounts
$AccountsRESTResponse = Get-TTAccounts -Environment $Environment

# Convert result to a hashtable
$AccountsHashTable = Convert-TTRESTObjectToHashtable -Objects $AccountsRESTResponse

$GHFSubAccountsRESTResponse = $AccountsRESTResponse | Where { $_.parentId -eq '46109' }
$MercurySubAccountsRESTResponse = $AccountsRESTResponse | Where { $_.parentId -eq '43698' }

$GHFSubAccountsRESTResponse | % { 




##############
# Get Mercury Positions
$PNLTable  = $positions | Where-Object { $_.AccountName -match 'LMERCURY' } | Select AccountName, Market, pnl | Group-Object -Property AccountName, Market

$test = @()

$test += foreach($item in $PNLTable){

    $item.Group | Select -Unique AccountName, Market,
    @{Name = 'PnL';Expression = {(($item.Group) | measure -Property pnl -sum).Sum}}

}

############

# Sum total PNL
$TotalPNL = "{0:c}" -f ($PNLTable | Measure-Object PnL -Sum).Sum

<# 
 PRINT TO SCREEN
#>
# Print PNL Table
$PNLTable | Select Name, @{N='PnL'; E={"{0:c}" -f $_.PnL}}  | Format-Table | Out-String| % {Write-Host $_}

# Print total PNL
Write-Host Total PNL: $TotalPNL
