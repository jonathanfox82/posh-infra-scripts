<#
.Synopsis
   RDS Maintenance Script
.DESCRIPTION
   This can be used for IT staff to maintain their RDS session hosts
.EXAMPLE
   RDS-Maintenance.ps1
.EXAMPLE
   RDS-Maintenance.ps1 -RDSBroker lcy-rds-br1.corp.hertshtengroup.com
 .VERSION 1.0
 Jonathan Fox
#>


Param
(
    [String]$RDSBroker="lonix-rds-br1.ghfinancials.co.uk"
)
function Restart-RDSSessionHost {
     param (
           [string]$serverName
     )
     Restart-Computer -ComputerName $serverName
}
function Show-Menu
{
     param (
           [string]$Title = "Choose an option from the list",
           [hashtable]$MenuOptions
     )
     cls

     Write-Host "================ $Title ================"
     Write-Host "Server: " $RDSBroker
     $MenuOptions.GetEnumerator() | sort -Property Name | ForEach-Object{
     $message = '{0}: {1}' -f $_.key, $_.value
     Write-Output $message
    }

}
function Print-RDSUsersessions {
    $sessions = Get-RDUserSession -ConnectionBroker $RDSBroker
    Write-Host ($sessions | Select CollectionName, UserName, HostServer | Format-Table | Out-String)
    Return $sessions
}

# VARIABLES BLOCK #
####################################################
$SMTPServer = "smtp.corp.hertshtengroup.com"
$emailTo = "server.engineering@hertshtengroup.com"
$emailFrom = "noreply@hertshtengroup.com"
####################################################

$User = ($env:UserName)

Write-Host Importing Remote Desktop module
Import-Module RemoteDesktop

$MainMenuList = @{
    1 = "Print a list of all current user sessions"
    2 = "Log of all sessions for a specific user"
    3 = "Log off all disconnected sessions"
    4 = "Reboot an RDS session host"
}

do
{
     Show-Menu -Title "Remote Desktop Services Maintenance Menu" -MenuOptions $MainMenuList
     $selection = Read-Host "Please make a selection or press q to quit"

     # Is this an Integer?
     if (($selection -match "^\d+$") -And ($MainMenuList.Keys) -contains $selection)
     {
            if ($selection -eq "1") {
                $RDSSessions = Print-RDSUsersessions
                Read-Host "Press enter key to go back to main menu ..."
                $selection -eq ""
            }
            elseif ($selection -eq "2") {
                $RDSSessions = Print-RDSUsersessions
                $UserNameResponse = Read-Host "Enter the username for the acount you wish to terminate all sessions for or press q to quit"
                if ( $UserNameResponse -eq "q" )
                {
                    Exit 
                }
                elseif ($RDSSessions.Username -contains $UserNameResponse)
                {
                    $RDSUserSessions = Get-RDUserSession -ConnectionBroker $RDSBroker | Where Username -eq $UserNameResponse

                    Write-Host logging off user sessions
                    Write-Host ($RDSUserSessions | Format-Table | Out-String)
                    $RDSUserSessions | ForEach-Object { Invoke-RDUserLogoff -HostServer $_.HostServer -UnifiedSessionID $_.UnifiedSessionID -Force}

                    Read-Host "Done, press enter key to exit..."
                    Exit
                }
                Read-Host "Invalid entry selected. Exiting"
                Exit
            }
            elseif ($selection -eq "3") {
                $DisconnectedSessions = Get-RDUserSession -ConnectionBroker $RDSBroker | Where-Object -Filter {$_.SessionState -eq 'STATE_DISCONNECTED'} 
                Write-Host "The following disconnected sessions will be logged off."
                Write-Host ($DisconnectedSessions | Select CollectionName, UserName, HostServer | Format-Table | Out-String)
                $DisconnectedSessions | ForEach-Object { Invoke-RDUserLogoff -HostServer $_.HostServer -UnifiedSessionID $_.UnifiedSessionID -Force}
                Read-Host "Press enter key to exit..."
                Exit
            }
            elseif ($selection -eq "4") {

                # Get a list of the session hosts
                $servers = Get-RDServer -ConnectionBroker $RDSBroker -Role "RDS-RD-Server" | Sort Server
                # Create a new hash table and populate it with the server list.
                $ServerList = @{}
                $a=1
                Foreach ($item in $servers) {
                    $ServerList.add($a, $item.Server)
                    $a++
                }
                do
                {
                    Show-Menu -Title "Choose a server from the list, careful with the numbering" -MenuOptions $ServerList
                    $ServerSelection = Read-Host "Please make a selection or press q to quit"
                   
                    if (($ServerList.Keys) -contains $ServerSelection) {
                        # A chance to change your mind
                        write-host  You have chosen to reboot server ($ServerList.[int]$ServerSelection)
                        write-host -nonewline "Continue? (Y/N) "
                        $response1 = read-host
                        if ( $response1 -ne "Y" ) { exit }
                        
                        Write-Host Restarting the server

                        Write-Host "Sending email notification"
                        $emailSubject = "RDS Session host " + ($ServerList.[int]$ServerSelection) + "Rebooted"
                        $emailBody = $User + "has initiated a reboot of the server " + ($ServerList.[int]$ServerSelection)
                        Send-MailMessage -To $emailTo  -From $emailFrom -Subject $emailSubject -SmtpServer $SMTPServer -Body $emailBody

                        Restart-Computer ($ServerList.[int]$ServerSelection)
                        Read-Host "Press enter key to exit..."
                        Exit
                    }
                }
                until ($ServerSelection -eq 'q')

            }
     }
}
until ($selection -eq 'q')