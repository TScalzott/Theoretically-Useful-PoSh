# Theoretically-Useful-PoSh
Various bits of PowerShell that may be handy to others.

## ActiveDirectory
    - Generate-Password.ps1
      Generate pseudo-random password(s) based on XKCD's Correct-Horse-Battery-Staple.  Optionally set the password in AD
      and share via OneTimeSecret.

    - Process-InactiveUsers.ps1
      Iterate domain(s) for users who have not signed in over a period of time.  Provide warnings up until
      a disable date.  Manager notification via email is also performed.

## M365
    - Licensed-DisabledUsers.ps1
      Flag users who are disabled in AD, but still have M365 licenses.

## Misc
    - Find-Process.ps1
      For all online endpoints in a domain or domains, audit for a currently running process. 

    - Find-Service.ps1
      Find installed services by checking all online endpoints from Active Directory

    - Ping-http.ps1
      For all entries in a hosts.txt file, repeatedly "ping" each site via https, recording some stats to the screen and 
      a logfile:

        Loaded 1 hosts to "ping" from C:\Users\me\Documents\hosts.txt
        Web hit timeout: 5 seconds.
        Delay between pings: 30
        Logging to C:\Users\me\Documents\Pinglog-me-2022-10-05.log

        10/5/2022 11:45:25 AM https://www.google.com: 464.1654ms Status OK 52603 bytes

    - Remove-StaleProfiles.ps1
      Based on last-used date, remove stale user profiles from the local or a remote system.


## profile
    - functions.ps1
      Various functions that can be dot-sourced from your PowerShell profile. The functions are aliased with a preceeding 
      moniker for easy identification and a "Show-Aliases" function is included as well to provide a synopsis.

## vSphere
    - Send-vSphereAlarms.ps1
      Grab any active vSphere alarms and post as cards to a Microsoft Teams channel.  Designed to be run periodically as a
      scheduled task.

    - Set-Syslog.ps1
      Quickly set the syslog server on all of your vSphere hosts.

