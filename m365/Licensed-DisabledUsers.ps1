#Requires -Modules ExchangeOnlineManagement, Microsoft.Graph.Users

Import-Module ExchangeOnlineManagement
Import-Module Microsoft.Graph.Users

$upn = Read-Host -Prompt "Enter M365 Admin UPN"
Connect-ExchangeOnline -UserPrincipalName $upn

Connect-MgGraph -Scopes "User.Read.All"

# Get our license SKU Id
$skuId = (Get-MgSubscribedSku |
  Where-Object {$_.SkuPartNumber -eq "ENTERPRISEPACK"}).SkuId

$OutputFile = "$($env:TEMP)\M365LicensedADDisabledUsers.csv"
$T1 = @()

Write-Output "Getting all Office 365 Users..."
$M365Users = Get-MgUser -All -Select userPrincipalName, assignedLicenses, assignedPlans |
  Sort-Object DisplayName

Write-Output "Processing all users against AD..."
ForEach ($M365User in $M365Users)
{
  $ADuser = Get-ADUser -Filter {UserPrincipalName -eq $M365User.UserPrincipalName} -Properties whenCreated,Enabled,manager
  If (($ADUser.Enabled -eq $false) -and ($M365User.AssignedLicenses.SkuId -contains $skuId))
  {
    $T1 += New-Object PSObject -Property @{
      'CollectionDate'    = $(Get-Date);
      'ADupn'             = $($ADUser.UserPrincipalName);
      'M365upn'           = $($M365User.UserPrincipalName);
      'WhenCreated'       = $($ADUser.whenCreated);
      'ADEnabled'         = $($ADUser.Enabled);
      'Licensed'          = $($ADUser.AssignedLicenses.SkuId -contains $skuId);
      'Manager'           = $ADuser.Manager
    }
  }
}

$T1 = $T1 |
  Sort-Object -Property WhenCreated
$T1 |  
  Format-Table -AutoSize -Wrap

$T1 |
  Export-Csv -Path $OutputFile -NoTypeInformation
Write-Output "Report written to $OutputFile"

