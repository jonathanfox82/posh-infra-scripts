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

# Remove module if it exists already
Remove-Module PSTTREST -ErrorAction SilentlyContinue

# Import Module 
Import-Module '.\PSTTREST.psm1' -ErrorAction Stop

################ VARIABLES BLOCK ###################
$baseURL = "https://apigateway.trade.tt"
$smtpServer = "smtp.ghfinancials.co.uk"
$fromAddress = "ttlimits@ghfinancials.com"
$subject = "TT Limits Report"
$date = (Get-Date).ToString('yyyyMMdd-HHmmss')
$logfile = "logs\$date.log"
####################################################
Start-Transcript -Path $logfile

$global:APIKey = ""
$global:APISecret = ""

Test-APIVars -ParamKey $TTAPIKey -ParamSecret $TTAPISecret

# Get an API token using module, this function sets the value of $APIToken globally.
Get-TTRESTToken -Environment $Environment

# if accounts is specified then just request those limits, otherwise get a list of all accounts and enumerate limits for all accounts.

if ($AccountsFilter) {
    $AllAccounts = [PSCustomObject]@{
        Id     = $AccountsFilter
    }
}
else {
    # Obtain accounts data.
    $AllAccounts = Get-TTAccounts -Environment $Environment
}


# Obtain Order Reference Data
$OrderData = (Invoke-RestMethod -Uri $baseURL/ledger/$Environment/orderdata -Method Get -Headers $DataRequestHeaders).orderData

$AllAccounts | % { 

    do {
        try {
            Write-Host "Getting Account Data for $($_.Id)"
            $AccountData = ""
            $AccountData = Invoke-RestMethod -Uri $baseURL/risk/$Environment/account/$($_.Id) -Method Get -Headers $DataRequestHeaders
        } catch {
            # Catch any errors such as Too Many Requests, throttle rate limit and try again until Status is Ok.#
            Write-Host "$(Get-TimeStamp) Error with REST Query "
            Write-Host "$(Get-TimeStamp) Using"
            Write-Host "$(Get-TimeStamp) API Key: $APIKey"
            Write-Host "$(Get-TimeStamp) Environment: $Environment"
            Write-Host "$(Get-TimeStamp) StatusCode:" $_.Exception.Response.StatusCode.value__ 
            Write-Host "$(Get-TimeStamp) StatusDescription:" $_.Exception.Response.StatusDescription
            Start-Sleep 0.2
        }
    }
    until ($AccountData.status -eq "Ok")

    $AccountDataArray += $AccountData.account
}


# Export as JSON
$AccountDataArray | ConvertTo-Json -Depth 10 | Out-File .\limits.json

#$AccountDataArray.Risklimits.ContractLimits | ft
#$AccountDataArray.Risklimits.productLimits | ft
#$AccountDataArray.Risklimits.productLimits | gm