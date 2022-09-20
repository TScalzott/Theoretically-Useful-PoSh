<#
.SYNOPSIS
    Post active vSphere alarms to a Microsoft Teams channel.

.DESCRIPTION
    Connect to the specified vSphere vCenter, query for all active alarms, and post those
    as a card to Microsoft Teams via a Webhook.

    The card will contain one section per alarm with a few facts:  the cluster involved,
    the date and time of the alarm, the alarm status (yellow/red/etc), and whether
    or not the alarm has been acknowledged.

    The card will also have a button to visit the vCenter UI while each (alarm) section
    has a button that goes directly to that object's summary tab in vCenter.

    Hat tip to @ericblee6, who pointed me toward @TheLazyAdmin's article below.  That gave
    me a new way to form the collections and format the webhook data.
    https://www.thelazyadministrator.com/2018/12/11/post-inactive-users-as-a-microsoft-teams-message-with-powershell/


.PARAMETER vCenter
    The vCenter server to be queried and linked to.

.PARAMETER TeamsUri
    Your Microsoft Teams WebHook URI.  To get this, add a Connector to a Teams Channel and
    copy the provided URL.

#>
param (
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$vCenter,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][uri]$TeamsUri
)

# Indicators found in MoRef for types of resources.
$clusterInd = "ClusterComputeResource-"
$hostInd = "HostSystem-"
$vmInd = "VirtualMachine-"

# Return active alarms from vCenter
function Get-Alarms() {
    [CmdletBinding()]
    param (
        [string]$vCenter
    )

    try {
        if ($global:DefaultVIServer.ServiceUri.Host -ne $vCenter) {
            Connect-VIServer $vCenter | Out-Null
    }
    # we need the Uuid for direct-reference vCenter URLs
    $Script:vcUuid = $global:DefaultVIServer.InstanceUuid.ToUpper()
}
catch {
    Write-Output "Failed to connect to $vCenter"
    return $null
}

$Clusters = Get-View -ViewType ComputeResource -Property Name, OverallStatus, TriggeredAlarmstate
$report = @()
$AlarmClusters = $Clusters | Where-Object { $null -ne $_.TriggeredAlarmState }

foreach ($ac in $AlarmClusters) {
    foreach ($ta in $ac.TriggeredAlarmstate) {
        $object = [PSCustomObject]@{
            'AlarmTime'       = (($ta.Time).ToLocalTime()).ToString()
            'AlarmStatus'     = $ta.OverallStatus.ToString()
            'AlarmAcked'      = $ta.Acknowledged
            'Cluster'         = $ac.Name
            'ImageUrl'        = ''
            'Entity'          = ''
            'Type'            = ''
            'MoRef'           = $ta.MoRef
            'TriggeredAlarms' = (Get-AlarmDefinition -Id $ta.Alarm.ToString()).Name
        }

        $entity = $ta.Entity.ToString()
        if ($entity -like "$($clusterInd)*") {
            $object.Entity = $ac.Name
            $object.Type = "Cluster"
            $object.MoRef = $ac.MoRef
            $object.ImageUrl = "https://i.imgur.com/iq2BkLQ.png"
        }
        elseif ($entity -like "$($hostInd)*") {
            $vmHost = Get-VMHost -Id $entity
            $object.Entity = $vmHost.Name
            $object.Type = "VMHost"
            $object.MoRef = $entity
            $object.ImageUrl = "https://i.imgur.com/k22bhCD.png"
        }
        elseif ($entity -like "$($vmInd)*") {
            $vm = Get-VM -Id $entity
            $object.Entity = $vm.Name
            $object.Type = "VM"
            $object.MoRef = $entity
            $object.ImageUrl = "https://i.imgur.com/Y0ShH0n.png"
        }

        $report += $object
    }
}
return $report
}

# Grab the alarms
Write-Output "Querying active vSphere alarms from $vcenter"
$Alarms = New-Object System.Collections.Generic.List[System.Object]
Get-Alarms($vcenter) |
    Sort-Object Cluster, Time, Entity |
    ForEach-Object {
        # throw into a collection consumable by Teams
        $Alarms.add($_)
    }

# Build the card sections, one per alarm. Stuff them into a collection
# consumable by Teams
$Sections = New-Object System.Collections.Generic.List[System.Object]
foreach ($a in $Alarms) {
    # Determine query string that lands us on our object in vCenter.  It uses the MoRef, but
    # with the first "-" replaced and the vCenter UUID
    $qs = "#?extensionId=vsphere.core.vm.summary&objectId=urn:vmomi:$($a.MoRef):$($vcUuid)"
    $qs = $qs -replace "(.*:vmomi:[a-z]+)-(.*)", '$1:$2' # adjust formatting

    $s = @{
        activityTitle     = $a.Entity
        activitySubtitle  = $a.Type
        activityText      = $a.TriggeredAlarms
        activityImage     = $a.ImageUrl
        activityImageType = "article"   # avoid rounded corner icons
        potentialAction   = @(
            @{
                '@type' = "OpenUri"
                name    = "Visit Object"
                targets = @(
                    @{
                        "os"  = "default"
                        "uri" = "https://$($vcenter)/ui/$($qs)"
                    }
                )
            }
        )

        facts             = @(
            @{
                name  = 'Cluster'
                value = $a.Cluster
            }
            @{
                name  = 'Alarm Time'
                value = $a.AlarmTime
            }
            @{
                name  = 'Alarm Status'
                value = $a.AlarmStatus
            }
            @{
                name  = 'Alarm Acked'
                value = $a.AlarmAcked
            }
        )
    }
    $Sections.Add($s)
}

# Post it if you got it
$count = $Sections.Count
if ($count -gt 0) {
    $text = "There $(if ($count -gt 1) {'are'} else {'is'}) $count active alarm$(if ($count -gt 1) {'s'} else {''}) at $(Get-Date)"
    Write-Output $text

    $body = ConvertTo-Json -Depth 8 @{
        title           = "Active vSphere Alarms via $($vCenter)"
        text            = $text
        sections        = $Sections
        potentialAction = @(
            @{
                '@context' = 'http://schema.org'
                '@type'    = "ViewAction"
                name       = "vCenter"
                target     = @("https://$($vcenter)/ui/")
            }
        )
    }

    Write-Output "Posting $($count) sections to WebHook $($TeamsUri)"
    Invoke-RestMethod -Uri $TeamsUri -Method Post -Body $body -ContentType 'application/json'
}
