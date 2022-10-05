<#
.SYNOPSIS
    Generate and optionally set a strong password.  
    Send a link to the password with OneTimeSecret if an email address is supplied.

.DESCRIPTION
    Uses the wordlist at correcthorsebatterystaple.net, based on https://xkcd.com/936/, to generate a random password
    that is largely pronouncable.

    If a username or UPN is supplied, the AD password will be reset to the last password generated.
    If an email address is supplied, the password is shared using OneTimeSecret.com

.EXAMPLE
    Generate-Password.ps1

    Output a generated password using the defaults
.EXAMPLE
    Generate-Password.ps1 -userName user@contoso.com

    Generate and set a password for "user@contoso.com"
.EXAMPLE
    Generate-Password.ps1 -userName user

    Generate and set a password for "user"
.EXAMPLE
    Generate-Password.ps1 -userName user -Recipient person@gmail.com

    Generate and set a password for "user", then email a OneTimeSecreet to "person@gmail.com"
#>

#Requires -Version 3
#Requires -Modules ActiveDirectory

[cmdletbinding(SupportsShouldProcess = $True)]
param (
    [Parameter(Mandatory = $false)][AllowEmptyString()][string]$userName = $null,
    [Parameter(Mandatory = $false)][string]$Recipient = $null,
    [Parameter(Mandatory = $false)][ValidateRange(1, 10)][int]$NumPass = 1,
    [Parameter(Mandatory = $false)][ValidateRange(1,5)][int]$NumWords = 3,
    [Parameter(Mandatory = $false)][ValidateLength(0, 1)][string]$Separator = '-'
)

function Get-UserDetails {
    [cmdletbinding(SupportsShouldProcess)]
    param([string]$userName)

    if ($userName) {
        if ($userName -match "^[^@]+@.+$") {
            $filter = "UserPrincipalName -eq ""$userName"""
        }
        else {
            $filter = "SamAccountName -eq ""$userName"""
        }

        try {
            $user = Get-ADUser -Filter $filter -ErrorAction Stop
        }
        catch { }
        if ($null -eq $user) {
            Write-Error "Unable to locate $userName"
            Exit
        }
    }
    $user
}

function Generate-Passwords {
    [cmdletbinding(SupportsShouldProcess)]
    param(
        [int]$numPass,
        [int]$NumWords,
        [string]$Separator
        )

    # Yay XKCD! https://xkcd.com/936/
    $WordListUrl = 'https://bitbucket.org/jvdl/correcthorsebatterystaple/raw/773dbccc9b9e1320f076c432d600f19785c41792/data/wordlist.txt'
    try {
        $words = (Invoke-WebRequest $WordListUrl -ErrorAction Stop |
                Select-Object -ExpandProperty Content).Split(',')
        Write-Information "Loaded $(($words.count).ToString('N0')) password words`n"
    }
    catch {
        Write-Error "Unable to download wordlist!"
        exit
    }

    # Generate.  If more than one is specified, the last one wins
    Write-Information "Generated Password(s):"
    for ($c = 1; $c -le $NumPass; $c++) {
        $Password = ForEach-Object { 
            "$([string]::Join($Separator,(1..$NumWords |
                ForEach-Object {
                    [cultureinfo]::CurrentCulture.TextInfo.ToTitleCase(($words |
                    Get-Random))}
                )))$Separator$((1..99 |
            Get-Random).ToString('00'))" 
        }

        Write-Information "   $($Password)"
    }
    $Password
}

function Share-Secret {
    [cmdletbinding(SupportsShouldProcess)]
    param(
        [string]$Recipient,
        [string]$Secret
    )

    # Send via OneTimeSecret
    if ($Recipient) {
        Write-Output "`nSharing Secret with $Recipient"

        $SecretUrl = 'https://onetimesecret.com/api/v1/share'
        $SecretAccount = ''  # Your OneTimeSecret account/username
        $SecretToken = ''  # Your OneTimeSecret API token
        $days = 3   # Number of days secret is kept

        $base64AuthInfo = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $SecretAccount, $SecretToken)))
        $Headers = @{
            Authorization = "Basic $($base64AuthInfo)"
        }
        $body = @{
            secret    = $Secret
            ttl       = ($days * 86400)
            recipient = $Recipient
        }
        if (-not ([bool]$WhatIfPreference.IsPresent)) {
            try {
                $Result = Invoke-RestMethod -Headers $Headers -Method 'Post' -Uri $SecretUrl -Body $body -ErrorAction Stop
            }
            catch {}
        }
        else {
            Write-Information "Whatif: No secret shared"
        }
    }
    $Result
}

<#
    here we go, here we go
#>

$InformationPreference = 'Continue' # output information
$commonParams = @{}
if ($WhatIfPreference.IsPresent) { $commonParams.Add('WhatIf', $true) }

# Validate our email address
if ($Recipient) {
    Write-Output "Checking $Recipient"
    $rfc5322 = "(?:[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*|""(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21\x23-\x5b\x5d-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])*"")@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\[(?:(?:(2(5[0-5]|[0-4][0-9])|1[0-9][0-9]|[1-9]?[0-9]))\.){3}(?:(2(5[0-5]|[0-4][0-9])|1[0-9][0-9]|[1-9]?[0-9])|[a-z0-9-]*[a-z0-9]:(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21-\x5a\x53-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])+)\])"
    if ($Recipient -notmatch $rfc5322) {
        Write-Output "Invalid recipient email address: $Recipient"
        exit
    }
}

# Avoid older TLS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($userName) {
    $user = Get-UserDetails $userName
    if ($user) {
        $user |
            Format-Table SamAccountName, UserPrincipalName, Name, Enabled
    }
}

$Password = Generate-Passwords -NumPass $NumPass -NumWords $NumWords -Separator $Separator
Write-Output "`nWinning Password: $Password`n"

if ($user) {
    Write-Output "`nSetting Password"
    try {
        $user |
            Set-ADAccountPassword -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $Password -Force) -ErrorAction Stop
        Write-Output "   Set!"

        try {
            Write-Output "   Requiring password change at next logon"
            $user | Set-ADUser -ChangePasswordAtLogon $true -ErrorAction Stop
            Write-Output "   Set!"
        } catch {
            Write-Output "   Failed to require password change!!"
        }
    }
    catch { Write-Output "   Failed to set!!" }
}

Share-Secret $Recipient $Password

Write-Output "`nDone!"
