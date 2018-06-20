<#
.Synopsis
   Get AWS Instance data and output to JSON file, uses recursive function Crawl-MetaData
.DESCRIPTION
   Recursively obtain the metadata from an AWS Instance.
   https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html
.EXAMPLE
   aws-get-metadata.ps1
   Get local AWS metadata and output to metadata.json
.EXAMPLE
   aws-get-metadata.ps1 -DataKey 'network'
   Starting at the network data key, crawl the instance metadata for information and output to JSON
.EXAMPLE
   Invoke-Command -ComputerName SVR1,SVR2,SVR3 -FilePath .\aws-get-metadata.ps1
   Run remote command to obtain metadata and output to console
#>
Param
(
    # Data key to start metadata crawl from e.g. network
    [Parameter(mandatory=$false)]
    [string]$DataKey
)

<# 
This function will invoke a request against the AWS instance data endpoint retrieving key value pairs into a hash table.
If it finds a value ending with "/"" that is a new key to crawl so the key becomes the key name and the value is a nested hashtable.
#>
function Crawl-MetaData($currentKey) {

        # Get the data for the current key
        try {
            $Data = Invoke-RestMethod -Uri $RootURL/$CurrentKey
        }
        catch {
            Write-Host "error getting data back from request"
        }

        # Initialise a hash table to store the results
        $SubHashTable = @{}

        foreach ($Line in $Data.Split([Environment]::NewLine)) {
            
            # Catch cases where there is an equals sign in the requests, e.g. public-keys.
            if ($Line -like "*=*") {
                $Line = $($Line.Split("=") | Select -First 1) + "/"
            }

            if ($Line.ToString().Substring($Line.Length - 1) -ne "/") {
                # this is a command that will return an actual value
                try {
                    $Result = Invoke-RestMethod -Uri "$RootURL/$CurrentKey/$Line"
                    # Add to this hashtable.
                    $SubHashTable.$Line = $result
                }
                catch {
                    Write-Host "error getting data back from request"
                }
            }
            else {
                if ($Line.ToString().Substring($Line.Length - 1) -eq "/") {
                    # This is a new key to crawl
                    $NewKey = $Line.Trim("/")
                    # Create a nested hashtable with keyname $NewKey and crawl this new key for metadata.
                    $SubHashTable.$NewKey = Crawl-MetaData($CurrentKey + '/' + $NewKey)
                }
            }
        }
        Return $SubHashTable
}

$global:JSONDoc = @{}
$global:RootURL = "http://169.254.169.254/latest"

# Get Metadata
$JSONDoc = Crawl-MetaData('meta-data/' + $DataKey)

# Write to JSON file
$JSONDoc | ConvertTo-Json -Depth 10 | Out-File .\metadata.json

# Test Output
$JSONDoc | ConvertTo-Json -Depth 10 | Out-String | Write-Host