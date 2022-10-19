<# 
Install all missing Remote Server Administration Tools. 
Windows 10 Feature Updates are reliably removing RSAT features.  This script adds them back.
#>
$Caps = Dism.exe /ONLINE /GET-CAPABILITIES
$Caps | Select-String -Pattern ' : (Rsat\..*)' -Context 0, 1 |
ForEach-Object { 
    if ($_.Context.PostContext -match "Not Present") {
        if ($_ -match ' : (Rsat\..*)') {
            $command = "DISM.EXE /Online /Add-Capability /CapabilityName:$($matches[1])"
            Write-Output "Invoking: $($command)"
            Invoke-Expression $command
        }
    }
}