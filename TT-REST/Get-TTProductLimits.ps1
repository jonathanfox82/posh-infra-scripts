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

# format HTTP header for data GET requests
$DataRequestHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$DataRequestHeaders.Add("x-api-key", $APIKey)
$DataRequestHeaders.Add("Authorization", 'Bearer '+ $APIToken )

# Obtain a REST response for accounts
$AccountsRESTResponse = Get-TTAccounts -Environment $Environment

# Get Limit information
$MercuryAccounts = $AccountsRESTResponse  | Where-Object { $_.name -match 'XG' }

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
$MarketsRESTResponse = Get-TTMarkets -Environment $Environment

$ProductTypeHT = Convert-TTRESTObjectToHashtable -Objects $ProductTypeData.productTypes
$MarketsHT = Convert-TTRESTObjectToHashtable -Objects $MarketsRESTResponse 
$AccountsHT = Convert-TTRESTObjectToHashtable -Objects $AccountsRESTResponse

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

# Create Hashtable for quicker lookup
$ProductsHT = @{} 
$ProductCache | Foreach { $ProductsHT[[uint64]$_.id] = $_.Name }

# Test speed of Hashtable vs Object lookup
Measure-Command { $ProductsHT[[uint64]3478261305138950000] }
Measure-Command { $ProductCache | Where-Object { $_.id -eq 3478261305138950000 } }

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

        $Account = $AccountsHT[[int]$AccountId]
        $Market = $MarketsHT[[int]$MarketId]
        $Product = $ProductsHT[[uint64]$ProductId]
        $ProductType = $ProductTypeHT[[int]$ProductTypeId]

        $ThisProductLimit | Add-Member -type NoteProperty -Name "Account" -Value $Account -Force
        $ThisProductLimit | Add-Member -type NoteProperty -Name "Market" -Value $Market -Force
        $ThisProductLimit | Add-Member -type NoteProperty -Name "Product" -Value $Product -Force
        $ThisProductLimit | Add-Member -type NoteProperty -Name "ProductType" -Value $ProductType -Force

        $ProductLimitArray += $ThisProductLimit
    }

}

$ProductLimitArray | Export-Csv -Notypeinformation .\limits.csv -Force