<#
.SYNOPSIS
Finding processes running / not running by checking all online endpoints from Active Directory

.DESCRIPTION
For each reachable endpoint in a set of domains, check for a running process and report
where it is found.

.PARAMETER Domains
Array of domains. All computers will be from each domain will be polled.

.PARAMETER Process
Name of process to be found. Can include wildcards.

.EXAMPLE
    Find-S1 -Domains @("contoso.com") -Process SentinelAgent*

.EXAMPLE
    Find-S1 -Domains @("contoso.com","fabrikam.com") -Process *Agent*

#>
param
(
    [Parameter(Mandatory = $True, ParameterSetName = 'ScanDomain')][string[]]$Domains,
    [Parameter(Mandatory = $True, ParameterSetName = 'ScanDomain')][string[]]$Process
)

# For speed, use Invoke-Ping from https://gallery.technet.microsoft.com/scriptcenter/Invoke-Ping-Test-in-b553242a
#
# Also use PoshRSJob https://github.com/proxb/PoshRSJob
#

#Requires -Module PoshRSJob
Import-Module PoshRSJob

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (Test-Path "$($scriptPath)\Invoke-Ping.ps1") {
    . "$($scriptPath)\Invoke-Ping.ps1"
} else {
    Write-Output "Please place Invoke-Ping.ps1 in the same path as this script."
    Write-Output "You can find Invoke-Ping at https://gallery.technet.microsoft.com/scriptcenter/Invoke-Ping-Test-in-b553242a"
    Exit
}

# Adjust if you wish. Filters for Get-ADComputer to retrieve only Servers and only Workstations.
$ServerFilter = "OperatingSystem -like '*Server*' -and enabled -eq 'True'"
$WSFilter = '(Enabled -eq $true) -and ((Operatingsystem -like "Windows*") -and (OperatingSystem -notlike "*Server*"))'

$Servers = @()
$Workstations = @()
foreach ($d in $Domains) {
    $Servers += (Get-ADComputer -Server $d -Filter $ServerFilter).Name
    $Workstations += (Get-ADComputer -Server $d -Filter $WSFilter).Name
}
Write-Output "Found $(($Servers | Measure-Object).Count) servers in Active Directory."
Write-Output "Found $(($Workstations | Measure-Object).Count) workstations in Active Directory."

$All = ($Servers | Sort-Object) + ($Workstations | Sort-Object)

Write-Output "Determining online endpoints..."
$Responding = ($All | Invoke-Ping -Quiet)
Write-Output "Found $($Responding.Count) online"

Write-Output "Finding instances of process ""$($Process)"""
$RSJobs = 20        # Number of outstanding runspace jobs at a time
$ScriptBlock = {
    $Results = [PSCustomObject]@{
        ComputerName = $_
        OS           = $null
        Instances    = $null
        Running      = $null
    }
    $Process = $using:Process

    try {
        $Results.Instances = (Get-Process -ComputerName $Results.ComputerName $Process -ErrorAction Stop).ProcessName
        $Results.OS = (Get-WmiObject -ComputerName $Results.ComputerName Win32_OperatingSystem).Caption
    }
    catch {
        continue
    }
    $Results.Running = (($Results.Instances).Count -gt 0)
    $Results
}

$AllResults = $Responding |
    Start-RSJob -ScriptBlock $ScriptBlock -Throttle $RSJobs |
    Wait-RSJob -ShowProgress |
    Receive-RSJob |
    Sort-Object ComputerName

Write-Output "Discovered $(($AllResults | Where-Object {$_.S1 -eq $True} | Measure-Object).Count) instances.`n"
$AllResults |
    Format-Table
$AllResults | Out-GridView
