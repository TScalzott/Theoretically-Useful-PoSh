#Requires -Version 3

<#
.SYNOPSIS
    Remove stale user profiles, based on last used date

.PARAMETER NumDays
    Number of days stale. Anything older than this will be removed
    
.PARAMETER computerName
    Remote system to operate on. "." for the local system.

.EXAMPLE
    Remove-StaleProfiles.ps1 60

#>
[cmdletbinding(SupportsShouldProcess = $True)]
param (
    [Parameter(Mandatory = $false)][int]$numDays = 60,
    [Parameter(Mandatory = $false)][AllowEmptyString()][string]$computerName = '.'
)

$staleDate = (Get-Date).AddDays( - ($numDays))
$LogFile = "\LogFiles\Remove-StaleProfiles\Remove-StaleProfiles-$((Get-Date -format 'yyyyMMdd')).log"

Write-Output "Searching for profiles older than $($numDays) days ago ($($staleDate))..." |
    Tee-Object -FilePath $LogFile -Append

$Stale = Get-WmiObject -Class Win32_UserProfile -ComputerName $computerName -Filter "Special = false" |
    Where-Object { $_.LocalPath -notmatch "\\(Admin|Owner)" -and ($_.ConvertToDateTime($_.LastUseTime) -lt $staleDate) }

if ($stale.Count -gt 0) {
    Write-Output "Removal candidates:" |
        Tee-Object -FilePath $LogFile -Append
    $Stale |
        Sort-Object LastUseTime, LocalPath |
        Select-Object PSComputerName, LocalPath, LastUseTime |
        Format-Table |
        Tee-Object -FilePath $LogFile -Append

    Write-Output "Removing..." |
        Tee-Object -FilePath $LogFile -Append
    $Stale | Remove-WmiObject -WhatIf:([bool]$WhatIfPreference.IsPresent)
    Write-Output "Done." |
        Tee-Object -FilePath $LogFile -Append
}
else {
    Write-Output "No candidates found." |
        Tee-Object -FilePath $LogFile -Append
}
