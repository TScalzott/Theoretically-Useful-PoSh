<#
.SYNOPSIS
Find installed services by checking all online endpoints from Active Directory

.DESCRIPTION
For each reachable endpoint in a set of domains, check for an installed service and
a similarly named path, if present.  Services are found not by name, but by PathName.

.PARAMETER Domains
Array of domains. All computers will be from each domain will be polled.

.PARAMETER PathName
Path of executable for the service. Can include wildcards.

.EXAMPLE
    Find-Service -Domains @("contoso.com") -PathName "*\Program Files\EMCO\*"

.EXAMPLE
    Find-Service -Domains @("contoso.com","fabrikam.com") -PathName "*\Program Files\EMCO\*"


Requires Invoke-Ping on the path. Get it at https://gallery.technet.microsoft.com/scriptcenter/Invoke-Ping-Test-in-b553242a
Also requires PoshRSJob https://github.com/proxb/PoshRSJob

#>

param
(
    [Parameter(Mandatory = $True, ParameterSetName = 'ScanDomain')][string[]]$Domains,
    [Parameter(Mandatory = $True, ParameterSetName = 'ScanDomain')][string[]]$PathName
)


#Requires -Module PoshRSJob
Import-Module PoshRSJob

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (Test-Path "$($scriptPath)\Invoke-Ping.ps1") {
    . "$($scriptPath)\Invoke-Ping.ps1"
}
else {
    Write-Output "Couldn't find $($scriptPath)\Invoke-Ping.ps1. Please place Invoke-Ping.ps1 in the same path as this script."
    Write-Output "You can find Invoke-Ping at https://gallery.technet.microsoft.com/scriptcenter/Invoke-Ping-Test-in-b553242a"
    Exit
}


$Servers = @()
$Workstations = @()
foreach ($d in $Domains) {
    $Servers += (Get-ADComputer -Server $d -Filter "OperatingSystem -like '*Server*' -and enabled -eq 'True'").Name
    $Workstations += (Get-ADComputer -Server $d -Filter '(Enabled -eq $true) -and ((Operatingsystem -like "Windows*") -and (OperatingSystem -notlike "*Server*"))').Name
}
Write-Output "Found $(($Servers | Measure-Object).Count) servers in Active Directory."
Write-Output "Found $(($Workstations | Measure-Object).Count) workstations in Active Directory."

# Add 'em all up and remote scan, if online.  You can run this multiple times
# because anything copied will use robocopy (but get the latest log)
$All = ($Servers | Sort-Object) + ($Workstations | Sort-Object)

Write-Output "Determining responding endpoints..."
$Responding = $All | Invoke-Ping -Quiet
Write-Output "Found $($Responding.Count) online"

$SearchPath = $PathName

$ScriptBlock = {
    $Results = [PSCustomObject]@{
        ComputerName = $_
        SystemName = $null
        Name = $null
        PathName = $null
        DisplayName = $null
        State = $null
        FoundPath = $null
        SearchPath = $using:SearchPath
    }
    try {
        $svc = Get-WmiObject -ComputerName $_ -Class Win32_Service -ErrorAction Stop |
            Select-Object SystemName, Name, Pathname, DisplayName, State |
            Where-Object { $_.PathName -like $Results.SearchPath }
        if ($svc) {
            $Results.SystemName = $svc.SystemName
            $Results.Name = $svc.Name
            $Results.PathName = $svc.PathName
            $Results.DisplayName = $svc.DisplayName
            $Results.State = $svc.State
        }
    }
    catch {}
    try {
        $Results.FoundPath = Get-ChildItem "\\$($_)$($SearchPath -Replace "*\", "\")" -Recurse -Directory |
            Select-Object -First 1 |
            Split-Path -Parent
    }
    catch {}

    if ($Results.Name -or $Results.FoundPath) {
        $Results
    }
}

Write-Output "Finding instances of services and paths matching ""$($SearchPath)"""
$RSJobs = 20        # Number of outstanding runspace jobs at a time
$Discovered = $Responding |
    Start-RSJob -ScriptBlock $ScriptBlock -Throttle $RSJobs |
    Wait-RSJob -ShowProgress |
    Receive-RSJob

Write-Output "Discovered $(($Discovered | Measure-Object).Count) instances.`n"
$Discovered |
    Format-Table
