$syslog = 'udp://1.2.3.4:514'    # change to your syslog host

$Hosts = Get-VMHost | Sort-Object Name
$Hosts | ForEach-Object {
    try {
        Write-Output "Setting $_ Syslog to $syslog"
        Set-VMHostSysLogServer -VMHost $_ -SysLogServer $syslog -ErrorAction Stop | Out-Null
    }
    catch [Exception] {
        Write-Output "  Operation failed."
        continue
    }
    $res = Get-VMHostSysLogServer -VMHost $_
    if ("$($res.Host):$($res.Port)" -eq $syslog) {
        # the setting took, add firewall exception and restart the service
        Write-Output "  Enabling syslog firewall exception on $_"
        Get-VMHostFirewallException -VMHost $_ -Name "syslog" | Set-VMHostFirewallException -Enabled:$true | Out-Null
        Write-Output "  Restarting Syslog on $_"
        $esxCli = Get-EsxCli -VMHost $_ -V2
        if ($esxCli.system.sysLog.reload.invoke()) {
            Write-Output "    Reloaded"
        }
    }
}
