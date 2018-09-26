<#
.Synopsis
   Get Limits
.DESCRIPTION
#>

Param
(
    # TT API Key
    [Parameter(mandatory=$false)]
    [string]$TTAPIKey,

    # TT API Key Secret part
    [Parameter(mandatory=$false)]
    [string]$TTAPISecret,

    # Filter by accountId?
    [Parameter(mandatory=$false)]
    $AccountsFilter,

    # TT Environment (default live)
    [Parameter(mandatory=$false)]
    [string]$global:Environment = "ext_prod_live"
)

Write-Host Importing TTREST Module
Remove-Module PSTTREST -ErrorAction SilentlyContinue
Import-Module '.\PSTTREST.psm1' -ErrorAction Stop

################ VARIABLES BLOCK ###################
$baseURL = "https://apigateway.trade.tt"
$smtpServer = "smtp.ghfinancials.co.uk"
$date = (Get-Date).ToString('yyyyMMdd-HHmmss')
$logfile = "logs\$date.log"
####################################################
Start-Transcript -Path $logfile

$global:APIKey = ""
$global:APISecret = ""

Test-APIVars -ParamKey $TTAPIKey -ParamSecret $TTAPISecret

# Get an API token using module, this function sets the value of $APIToken globally.
Get-TTRESTToken -Environment $Environment

# Obtain a REST response for markets
$MarketsData = Get-TTMarkets -Environment $Environment
# Convert markets object to a hashtable
$MarketsHashTable = Convert-TTRESTObjectToHashtable -Objects $MarketsData 


$PositionsData = Invoke-WebRequest -Uri "https://apigateway.trade.tt/monitor/ext_prod_live/position?scaleQty=0" -Method Get -Headers $DataRequestHeaders


# Get all products across all markets
$AllProducts = @()
$MarketsData | % {
    Write-Host "$(Get-TimeStamp) Getting products for $($_.name)"
    $Products = Get-TTProducts -Environment $Environment -MarketId $_.Id
    $AllProducts += $Products
}

# Obtain Reference Data
$OrderData = (Invoke-RestMethod -Uri $baseURL/ledger/$Environment/orderdata -Method Get -Headers $DataRequestHeaders).orderData
$ProductData = (Invoke-RestMethod -Uri $baseURL/pds/$Environment/productdata -Method Get -Headers $DataRequestHeaders).productTypes
$CurrencyData = (Invoke-RestMethod -Uri $baseURL/pds/$Environment/productdata -Method Get -Headers $DataRequestHeaders).currencies
$Orders = (Invoke-RestMethod -Uri $baseURL/ledger/$Environment/orders -Method Get -Headers $DataRequestHeaders).orders


Exit

$Instruments = Import-Clixml -path T:\Automations\TTREST-Scripts\instruments.xml

$instruments.GetEnumerator() | Select `
@{Name="Market";Expression={$_.value.Market}}, `
@{Name="ProductSymbol";Expression={$_.value.ProductSymbol}},`
@{Name="TickValue";Expression={$_.value.tickValue}}, `
@{Name="TickSize";Expression={$_.value.tickSize}}, `
@{Name="PointValue";Expression={$_.value.PointValue}}

$instruments.GetEnumerator() | Select `
@{Name="Market";Expression={$_.value.Market}}, `
@{Name="ProductSymbol";Expression={$_.value.ProductSymbol}}, `
@{Name="TickValue";Expression={$_.value.tickValue}}, `
@{Name="TickSize";Expression={$_.value.tickSize}},  -Unique | Sort-Object Market, Productsymbol | FT

Exit

# Declare New Empty Array
$instArray = @()

# Convert Nested HashTable to Object Array
$instruments.GetEnumerator() | % { $instArray += $_.Value }


$instArray | Select-Object Market, productSymbol -Unique | Sort-Object Market, productSymbol


<#
$ProductDetails = (Invoke-RestMethod -Uri $baseURL/pds/$Environment/product/5063277666235405 -Method Get -Headers $DataRequestHeaders).product

# Export Products as JSON
$AllProducts | ConvertTo-Json -Depth 10 | Out-File .\products.json

Write-Host "$(Get-TimeStamp) Getting product details"
$AllProductDetails = @()
$AllProducts | % {
    $ProductDetails = Get-TTProductDetail -Environment $Environment -ProductId $($_.id)
    $AllProductDetails += $ProductDetails
}
$AllProductDetails | ConvertTo-Json -Depth 10 | Out-File .\productDetails.json

<#
$ProductFamily = (Invoke-RestMethod -Uri $baseURL/pds/$Environment/productfamily?productFamilyId=17747093954586432734 -Method Get -Headers $DataRequestHeaders).productFamily
$ProductFamilyDetails = (Invoke-RestMethod -Uri $baseURL/pds/$Environment/productfamily/17747093954586432734 -Method Get -Headers $DataRequestHeaders).productFamily
$ProductDetail = Invoke-RestMethod -Uri $baseURL/pds/$Environment/product/5782397459325312 -Method Get -Headers $DataRequestHeaders
#>