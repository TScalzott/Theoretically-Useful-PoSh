<#
.SYNOPSIS
Load/unload all discovered user hives into the registry

.DESCRIPTION
For the local machine, load all discovered user hives.  Provide the option to then come
back and unload those same hives.

Why might you want to do this:

    For scanning for viruses/malware, you want to insure that all
    user keys are scanned as well.

    Making a registry change for all local machine users.

.EXAMPLE
   Load-UserHives.ps1 [-unload]

#>
param (
    [Parameter(Mandatory = $false)][switch]$unload
)

$KeyPrefix = "temp-"    # Append to each loaded hive as a key name

function Get-Confirmation($prompt) {
    # Return $true if we get a "Yes"
    #
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Off we go!"
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Abort!  Abort!"
    $options = [System.Management.Automation.Host.ChoiceDescription[]] ($yes, $no)

    ($host.ui.PromptForChoice($null, $prompt, $options, 1) -eq 0)
}

if (-not $unload.IsPresent) {
    $users = (Get-ChildItem -path ($env:USERPROFILE | Split-Path -Parent)).name
    [gc]::collect()
    Write-Output "Found $(($users | Measure-Object).Count) user folders."

    if (Get-Confirmation("Load all user hives?")) {
        foreach ($u in $users) {
            # Load, but not our own which is already loaded
            if ($u -notlike $env:USERNAME) {
                Write-Output "Loading to HKU\$($KeyPrefix)$($u)..."
                REG LOAD "HKU\$($KeyPrefix)$($u)" "C:\Users\$($u)\NTUSER.DAT"
            }
            else {
                Write-Output "Skipping current user $($u)"
            }
        }
    }
}
else {
    $hives = (Get-ChildItem -Path Registry::HKEY_USERS\$($KeyPrefix)*).Name
    [gc]::collect()  # Free what we can in hopes of successful unloads
    $count = ($hives | Measure-Object).Count
    Write-Output "Found $($count) loaded hives."

    if ($count -gt 0) {
        $prompt = "Unload all loaded user hives?"
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Off we go!"
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Abort!  Abort!"
        $options = [System.Management.Automation.Host.ChoiceDescription[]] ($yes, $no)

        if (Get-Confirmation("Unload all loaded user hives?")) {
            foreach ($h in $hives) {
                Write-Output "Unloading $($h)..."
                REG UNLOAD "$($h)"
            }
        }
    }
}
Write-Output "Done."