[string]$baseURL = "https://apigateway.trade.tt"
[string]$APIKey = "e202594b-a781-3c24-a01f-7cefd0818e15"
[string]$APISecret = "e202594b-a781-3c24-a01f-7cefd0818e15:5765df41-3c24-a8a8-5277-34c92428c68e"
[string]$Environment = "ext_prod_live"

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


$APIToken = (Invoke-RestMethod -Uri $baseURL/ttid/$Environment/token -Method Post -Body $body -Headers $GetTokenHeaders -ContentType 'application/json').access_token

$DataRequestHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$DataRequestHeaders.Add("x-api-key", $APIKey)
$DataRequestHeaders.Add("Authorization", 'Bearer '+ $APIToken )

try {

$positions = (Invoke-RestMethod -Uri $baseURL/monitor/$Environment/position?scaleQty=0 -Method Get -Headers $DataRequestHeaders -ContentType 'application/json').positions
$accounts = Invoke-RestMethod -Uri $baseURL/risk/$Environment/accounts -Method Get -Headers $DataRequestHeaders -ContentType 'application/json'

}
catch {
    Write-Host "Error with Invoke-RestMethod"
    Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ 
    Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
}
