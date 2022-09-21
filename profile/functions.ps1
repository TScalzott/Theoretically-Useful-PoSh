<#

Various PowerShell functions that I like to throw into $profile

#>

$Moniker = "IT"  # prefix alias descriptions with this moniker, allowing show-aliases and similar

function Get-Drives-func {
    [cmdletbinding()] param (
        [string] $computerName = "." )

    Process {
        $Drives = Get-CimInstance -Class Win32_LogicalDisk -Filter "DriveType = '3'" -ComputerName $computerName

        $Drives | Select-Object DeviceID, VolumeName,
            @{name = 'Size'; Expression={ [math]::round($_.Size / 1GB, 2)} },
            @{name = 'Free'; Expression = { [math]::round($_.FreeSpace / 1GB, 2)}} |
            Format-Table -AutoSize
    }
}
Set-Alias -Name Get-Drives -Value Get-Drives-func -Description "$($Moniker): Get system drives, size, freespace"

function Tail-func {
    # Make a tail equivalent to watch a file
    [cmdletbinding()] param (
        [Alias('File')][string] $TextFile )
    Process {
        Get-Content -tail 10 -wait -Encoding Unicode $TextFile
    }
}
Set-Alias -Name tail -Value Tail-func -Description "$($Moniker): Tail the contents of a file"

function Get-UTC-func {
    param (
        [string] $datetime = (Get-Date).ToString()
    )
    (Get-Date($datetime)).ToUniversalTime().ToString("o")
}
Set-Alias -Name Get-UTC -Value Get-UTC-func -Description "$($Moniker): Convert current or supplied datetime to UTC"

function Find-NameNumber-func {
    [cmdletbinding()] param (
        [string] $number )
    Process {
        $filter = "telephoneNumber -like ""*$($number)*"" -or mobile -like ""*$($number)*"""
        Get-ADUser -filter $filter -Properties Name, TelephoneNumber, Mobile, OtherTelephone, PhysicalDeliveryOfficeName |
            Select-Object Name, TelephoneNumber, Mobile, OtherTelephone, PhysicalDeliveryOfficeName |
            Format-Table -Autosize
    }
}
Set-Alias -Name Find-NameNumber -Value Find-NameNumber-func -Description "$($Moniker): Find name by number"

function Find-Number-func {
    [cmdletbinding()] param (
        [string] $name )
    Process {
        $filter = "name -like ""*$($name)*"" -and (mobile -like ""*"" -or telephoneNumber -like ""*"")"
        Get-ADUser -filter $filter -Properties Name, TelephoneNumber, Mobile, OtherTelephone, mail, PhysicalDeliveryOfficeName |
            Select-Object Name, TelephoneNumber, Mobile, OtherTelephone, Mail, PhysicalDeliveryOfficeName |
            Format-Table -Autosize
    }
}
Set-Alias -Name Find-Number -Value Find-Number-func -Description "$($Moniker): Find number by name"

function VM-Console-func {
    [cmdletbinding()] param (
        [string] $VMname )
    Process {
        try {
            vCenter
            Get-VM $VMname -ErrorAction Stop |
                Open-VMConsoleWindow -ErrorAction Stop
        }
        catch { Write-Output "Failed" }
    }
}
Set-Alias -Name VM-Console -Value VM-Console-func -Description "$($Moniker): Connect to a named VM's console window"


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

function Get-LAPS-func {
    [cmdletbinding()] param (
        [string] $computerName = "." )
    Process {
        Get-ADComputer $computerName -Properties Name, ms-Mcs-AdmPwd, OperatingSystem, distinguishedName |
            Select-Object @{Label = "Name"; Expression = { $_.name } },
                @{Label = "Password"; Expression = { $_.'ms-Mcs-AdmPwd' } },
                @{Label = "OS"; Expression = { $_.operatingsystem } },
                @{Label = "Distinguished name"; Expression = { $_.'distinguishedname' } }
    }
}
Set-Alias -Name Get-LAPS -Value Get-LAPS-func -Description "$($Moniker): Get LAPS password of local or remote system"

function show-aliases-func {
    # Remind us of our aliases
    Write-Output "Our Aliases:"
    Get-Alias |
        Where-Object { $_.Description -like "$($Moniker):*" } |
        Select-Object Name, @{N = "Description"; E = { $_.Description -Replace "$($Moniker): ", "" } } |
        Sort-Object Name
}
Set-Alias -Name Show-Aliases -Value show-aliases-func -Description "$($Moniker): Show my aliases"

Show-Aliases
