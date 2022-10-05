#Requires -modules ActiveDirectory
<#
.SYNOPSIS
    Disable inactive users in AD

.DESCRIPTION
    Find and warn inactive users, notify their manager, and disable after x days.

    The first notification is at $DaysInactive.  Subsequent notifications are then sent on each run until
    the $DaysDisable inactive time, at which time a final notification is sent and the account is disabled.

    Supports -WhatIf

.PARAMETER DaysInactive
    The number of days an account is inactive before an email is sent

.PARAMETER DaysDisable
    The number of days an account is inactive before it is disabled.

.PARAMETER DaysGrace
    Extra grace period in days for disabling, for special cases.  This is effectively added to DaysDisable.

.PARAMETER Domains
    Array of Active Directory Domains to check

.PARAMETER OnLeaveDN
    The distinguished name of a security group who's members will be EXCLUDED from action

.PARAMETER ExcludedDesc
    A regular expression that, if matched against user Description attribute, will be excluded from action.
    This is handy for shared/resource accounts, tenured folks, etc.

#>

<#
*******

Adjust the below defaults accordingly for your environment.  There are also 2 email message bodies further down
that you will want to adjust.

*******
#>
[cmdletbinding(SupportsShouldProcess = $True)]
param(
    [Parameter(Mandatory = $false)][int]$DaysInactive = 80,
    [Parameter(Mandatory = $false)][int]$DaysDisable = 90,
    [Parameter(Mandatory = $false)][int]$DaysGrace = 0,
    [Parameter(Mandatory = $false)][string[]]$domains = @("yourdomain.com"),
    [Parameter(Mandatory = $false)][string]$OnLeaveDN = "",
    [Parameter(Mandatory = $false)][string]$ExcludedDesc = "^\(?.*(Tenured-|Built\-in|Service|Shared|Resource|MBX).*",

    <# Adjust these below #>
    [Parameter(Mandatory = $false)][string]$SmtpServer = "yoursmtp.yourdomain.com",
    [Parameter(Mandatory = $false)][string]$MailFrom = "YourFriendlyAdmin@yourdomain.com",
    [Parameter(Mandatory = $false)][string]$MailBcc = "YourFriendlyAdminShared@yourdomain.com",
    [Parameter(Mandatory = $false)][string]$WarnSubject = "ACTION REQUIRED: Stale Account",
    [Parameter(Mandatory = $false)][string]$DisableSubject = "ACTION REQUIRED: DISABLED Account"
)

Import-Module ActiveDirectory

if (-not (Test-Path "\Logfiles")) {
    New-Item -Path "\LogFiles" -ItemType Directory
}
$LogFile = "\LogFiles\Process-InactiveUsers-$((Get-Date -format 'yyyyMMdd')).log"

$BadUsers = @()
$staletime = (Get-Date).Adddays( - ($DaysInactive))

Write-Output "$(Get-Date -Format 'dd/MM/yyyy hh:mm') Finding inactive users > $($DaysInactive) and disabling > $($DaysDisable). Grace: $($DaysGrace)" |
    Tee-Object -FilePath $LogFile -Append

foreach ($domain in $domains) {

    Write-Output "$(Get-Date -Format 'dd/MM/yyyy hh:mm') Domain: $($Domain)" |
        Tee-Object -FilePath $LogFile -Append

<#
 Get all enabled users with a lastLogonTimestamp less than our inactive time
 Rub:  A user may have never logged in and we still want to disable that account. In that case, we need
 to look at whenCreated instead.
#>
    $filter = "(enabled -eq 'True' -and name -notlike ""*$"") -and -not (memberOf -RecursiveMatch ""$OnLeaveDN"")"
    $StaleUsers = Get-ADUser -Server $domain -filter $filter `
        -Properties LastLogonTimeStamp, Description, Department, Manager, physicalDeliveryOfficeName, mail, whenCreated |
        Where-Object { ($_.LastLogonTimeStamp -eq $null -or [datetime]::FromFileTime($_.LastLogonTimeStamp) -lt "$staletime") -and
            $_.WhenCreated -lt $staletime -and
            $_.Description -notmatch $ExcludedDesc } |
            Sort-Object PhysicalDeliveryOfficeName, Name

    Write-Output "$(Get-Date -Format 'dd/MM/yyyy hh:mm') Stale users found: $(($StaleUsers | Measure-Object).Count)" |
        Tee-Object -FilePath $LogFile -Append

    foreach ($u in $StaleUsers) {
        try {
            $Manager = (Get-ADUser -Server $domain $u.manager -Properties mail).mail
        }
        catch {
            $Manager = $null
        }

        # There is a special case for accounts that have been created over the DaysInactive threshold.
        # They will show up here, but the LastLogonTimestamp will be null and the DaysSince calculation
        # goes to a large value, resulting in them getting disabled.  So we'll make it the same as the WhenCreated
        # meaning that the not-signed-in account gets disabled based on the established timing.
        if ($null -eq $u.lastLogonTimestamp) {
            $u.lastLogonTimestamp = ($u.whenCreated).ToFileTime()
        }

        $BadUsers += New-Object PsObject -Property @{
            Name        = $($u.Name);
            DN          = $($u.DistinguishedName);
            LastLogon   = $([DateTime]::FromFileTime($u.lastLogonTimestamp));
            DaysSince   = [math]::min( ((New-TimeSpan -Start ([DateTime]::FromFileTime($u.lastLogonTimestamp))).Days ), `
                ( (New-TimeSpan -Start ([DateTime]::FromFileTime($u.lastLogon))).Days));
            Office      = $($u.PhysicalDeliveryOfficeName);
            Mail        = $($u.mail);
            ManagerMail = $($Manager);
            Department  = $($u.Department);
            Description = $($u.Description);
            Domain      = $Domain;
        }
    }
}

foreach ($u in $BadUsers) {
    $MsgWarnBody =
    @"
<html><body>

Hello,
<p>

This message is to inform you that one of your direct reports, <u>$($u.Name)</u>, has not signed in for $($u.DaysSince) days.
<p>

<b>At $($DaysDisable) days their account will be automatically disabled.
Once the account is disabled, the <i>mailbox will be automatically purged</i> within a few days and the Office 365 license reclaimed.</b>
<p>

In order to fulfill our compliance obligations, any account that has not signed in for more than $($DaysDisable) days is <i>automatically</i>
disabled.  The use of email via mobile device or webmail is not suitable as a means of detection--an unattended personal mobile
device can continue to check for email after employee separation.
<p>

<p>

Thank you.
</body></html>
"@

    $MsgDisableBody =
    @"
<html><body>

Hello,
<p>

This message is to inform you that one of your direct reports, <u>$($u.Name)</u>, has not signed in for $($u.DaysSince) days.
<p>

<b>Their account has been automatically disabled and the <i>mailbox will be automatically purged</i> within a few days.</b>
<p>

<span style="color:red">If there has been a separation of employment, or you believe that you have received this message in error, please notify <a href=mailto:Internal-IT@kastle.com>I.T.</a> immediately.</span>
<p>

Thank you.
</body></html>
"@

    Write-Output "$(Get-Date -Format 'dd/MM/yyyy hh:mm') $($u.name): Days Since: $($u.DaysSince)" |
        Tee-Object -FilePath $LogFile -Append

    # If right at the DaysDisable OR >= DaysDisable + Grace, disable.  This means any newly-approaching DaysDisable get
    # Disabled but any already past $DaysDisable might get a $DaysGrace grace period
    if (($u.DaysSince -eq $DaysDisable) -or
        ($u.DaysSince -ge ($DaysDisable + $DaysGrace))) {
        Write-Output "$(Get-Date -Format 'dd/MM/yyyy hh:mm') ***Disabling: $($u.Name)" |
            Tee-Object -FilePath $LogFile -Append
        Set-ADUser -Server $u.Domain $u.DN -enabled $false -WhatIf:([bool]$WhatIfPreference.IsPresent) | 
            Tee-Object -FilePath $LogFile -Append

        Write-Output "$(Get-Date -Format 'dd/MM/yyyy hh:mm') Emailing $($u.ManagerMail) regarding $($u.Name) DISABLED." |
            Tee-Object -FilePath $LogFile -Append

        if (-not $WhatIfPreference.IsPresent) {
            Send-MailMessage -Body $MsgDisableBody -BodyAsHtml -From $MailFrom -Subject $DisableSubject `
                -To $u.ManagerMail -Bcc $MailBcc -SmtpServer $SmtpServer -Priority High
        }
    }

    # Mail if between DaysDisable and DaysInactive AND every 2 days
    if ($u.DaysSince -ge $DaysInactive -and
        $u.DaysSince -le ($DaysDisable + $DaysGrace) -and
        ($u.DaysSince - ($DaysInactive - 1)) % 2 ) {
        Write-Output "$(Get-Date -Format 'dd/MM/yyyy hh:mm') Emailing $($u.ManagerMail) regarding $($u.Name) for $($u.DaysSince) days." |
            Tee-Object -FilePath $LogFile -Append

        if (-not $WhatIfPreference.IsPresent) {
            # Send twice to avoid a failure to send at all if one address fails.
            Send-MailMessage -Body $MsgWarnBody -BodyAsHtml -From $MailFrom -Subject $WarnSubject `
                -To $u.ManagerMail  -Bcc $MailBcc -SmtpServer $SmtpServer -Priority High
            Send-MailMessage -Body $MsgWarnBody -BodyAsHtml -From $MailFrom -Subject $WarnSubject `
                -To $u.Mail  -Bcc $MailBcc -SmtpServer $SmtpServer -Priority High
        }
    }
}

if ([Environment]::UserInteractive) {
    $BadUsers | Out-GridView
}
else {
    $BadUsers | Export-Csv "InactiveUsers-$((Get-Date -format 'yyyyMMdd')).csv" -NoTypeInformation
}
