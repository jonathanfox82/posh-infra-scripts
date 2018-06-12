This set of scripts will enable you to query the TT REST API via a PowerShell module, we use this to create reports on SOD, Fills, Positions etc.



You need to either supply your API key and Secret on the command line 
    e.g.    Get-TTSODs.ps1 -APIkey "myapikey" -APISecret "myapisecret" -Environment "ext_prod_live"

Or set these 2 environment variables

setx -m TT_RESTAPI_KEY YOURAPIKEY

setx -m TT_RESTAPI_SECRET YOURAPISECRET

Any vars specified via command line will override the environment variables.

Once this is done a command like Get-TTSODs.ps1 should work with no variables needing to be passed.
