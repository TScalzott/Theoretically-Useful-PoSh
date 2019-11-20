<#

Various PowerShell functions that I like to throw into $profile

#>

$Moniker = "IT"  # prefix alias descriptions with this moniker, allowing show-aliases and similar

function list-proc-func {
    # Make a remote process list and pipe that into
    # a grid view, where selected processes can be terminated
    [cmdletbinding()] param (
        [string] $computerName = "." )

    Process {
        Get-WmiObject Win32_Process -ComputerName $computerName |
            Sort-Object Name |
            Select-Object @{N = 'PID'; E = { $_.ProcessId } },
            @{N = 'Parent'; E = { $_.ParentProcessId } },
            Name,
            @{N = 'Command'; E = { $_.CommandLine } },
            @{N = 'Object'; E = { $_ } } |
            Out-GridView -PassThru -Title "Process List. Select to KILL." |
            ForEach-Object {
                Write-Output "Terminating: $($_.Object.ProcessName)"
                $_.Object.Terminate() | Out-Null
            }
    }
}
Set-Alias -Name List-Proc -Value List-Proc-func -Description "$($Moniker): Process List. Optional computerName"

function Top-Dir-func {
    # Make a top-x directory listing
    [cmdletbinding()] param (
        [string] $pathSpec,
        [int] $Top = 15)
    Process {
        Get-ChildItem $pathSpec |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $Top
    }
}
Set-Alias -Name Top-Dir -Value Top-Dir-func -Description "$($Moniker): Top x directory sorted by last modified"

function Get-Uptime-func {
    # Get computer uptime, build info, and last updates
    [cmdletbinding()] param (
        [string]$computerName = '.' )
    Process {
        $Versions = @{
            "10586" = "November version: 1507";
            "14393" = "Anniversary: 1607";
            "15063" = "Creators: 1703";
            "16299" = "Fall Creators: 1709";
            "17134" = "April 2018: 1809";
            "17763" = "October 2018: 1809";
            "18362" = "May 2019: 1903";
            "18363" = "November 2019: 1909"
        }

        if (($computerName -eq ".") -or (Test-Connection $computerName -Count 2 -Quiet)) {
            Write-Output "Getting uptime for $($computerName)"
            Get-WmiObject Win32_OperatingSystem -ComputerName $computerName |
                Select-Object @{n = 'System'; e = { $_.csname } },
                @{n = 'Last Boot'; e = { $_.ConverttoDateTime($_.LastBootupTime) } },
                Caption,
                BuildNumber,
                @{n = 'Version'; e = { $Versions[[string]$_.BuildNumber] } },
                OSArchitecture,
                @{n = 'RAM(GB)'; e = { [math]::round($_.TotalVisibleMemorySize / 1MB) } }
            Try {
                Write-Output "`nLast update installed:"
                Get-HotFix -ComputerName $computerName -ErrorAction SilentlyContinue |
                    Sort-Object InstalledOn -Descending -ErrorAction SilentlyContinue |
                    Select-Object HotFixID, Description, InstalledOn -First 1
            }
            catch { }
        }
        else {
            Write-Output "$($computerName) is offline."
        }
    }
}
Set-Alias -Name Get-Uptime -Value Get-Uptime-func -Description "$($Moniker): Get uptime of local or remote system"

function show-aliases-func {
    # Remind us of our aliases
    Write-Output "Our Aliases:"
    Get-Alias |
        Where-Object { $_.Description -like "$($Moniker):*" } |
        Select-Object Name, @{N = "Description"; E = { $_.Description -Replace "$($Moniker): ", "" } } |
        Sort-Object Name
}
Set-Alias -Name Show-Aliases -Value show-aliases-func -Description "$($Moniker): Show my aliases"
