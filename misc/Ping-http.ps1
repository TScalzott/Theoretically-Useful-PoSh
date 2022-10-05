<#

"Ping," via https, the hosts specified in hosts.txt file, one per line

For each, record date and time, ms to access, number of bytes returned, and status code.
Flag failures with ***

A daily log file is kept along with the screen output

Both the source hosts file (hosts.txt) and log files are homed to the user's Documents folder.

#>
[CmdletBinding()]
param(
    [string] $inputFile = "$($env:USERPROFILE)\Documents\hosts.txt",
    [int] $timeout = 5,
    [int] $delay = 30
)


try {
    $hosts = Get-Content $inputFile
    Write-Output "Loaded $($hosts.Count) hosts to ""ping"" from $($inputFile)"
}
catch {
    Write-Output "Unable to load $($inputFile)"
    exit
}
Write-Output "Web hit timeout: $($timeout) seconds.`nDelay between pings: $($delay)"

while ($true) {
    $lastFile = $outputFile
    $outputFile = "$($env:USERPROFILE)\Documents\Pinglog-$($env:USERNAME)-$((Get-Date).ToString('yyyy-MM-dd')).log" # daily file
    if ($lastFile -ne $outputFile) {
        Write-Output "Logging to $($outputFile)`n"
    }

    foreach ($h in $hosts) {
        if ($h -notlike 'http*') {
            $h = 'https://' + $h    # ensure https
        }
        $now = Get-Date -Format G
        try {
            $measure = Measure-Command {
                $result = Invoke-WebRequest $h -TimeoutSec $timeout
                }
            $msg = "$($h): $($measure.TotalMilliseconds)ms Status $($result.StatusDescription) $($result.RawContentLength) bytes"
            if ($result.StatusCode -ne 200) {
                $msg = "*** $($msg)"  # Searchable flag
            }
            Write-Output "$($now) $($msg)" |
                Tee-Object $outputFile -Append
        }
        catch {
            Write-Output "$($now) $($h) FAILED" |
                Tee-Object $outputFile -Append
        }
    }
    Write-Output "---------------`n" |
        Tee-Object $outputFile -Append

    Start-Sleep -Seconds $delay
}
