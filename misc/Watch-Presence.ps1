function Watch-Presence-func {
	<# 
	  Get status information from the MS Teams log and pass that along to a webhook into
	  Home Assistant.  
	  
	  Create the webhook in HA via an automation with a webhook trigger, which will generate
	  the id to be used below.  For the automation action, you can change a helper based off
	  trigger.query['status'].  
	  
	  I like to mimic the Teams colors of Green, Yellow, Red and cast that at the office door with 
	  a WLED-driven light.
	  
	  Status values that have been observed and can be returned are Available, Away, Busy, DoNotDisturb,
	  InAMeeting, OnThePhone, Presenting, Unknown
	#>
	$webhook_id = "your-webhook-id-here"
	$ha_url = "http://homeassistant:8123/api/webhook/$($webhook_id)"
	$teams_log = "$env:APPDATA\Microsoft\Teams\logs.txt"
	Get-Content $teams_log -Wait -Tail 0 | 
		Where-Object { $_ -match "(?<=StatusIndicatorStateService: Added )(\w+)" } |
		ForEach-Object {
			if ($matches[0] -ne "NewActivity") {
				$post = "$($ha_url)?status=$($matches[0])"
				Write-Output "$((Get-Date -Format "MM/dd/yyyy HH:mm:ss")): $($post)"
				$status = (Invoke-WebRequest -Uri $post -Method POST).StatusCode
				if ( $status -ne 200) {
					Write-Output "$((Get-Date -Format "MM/dd/yyyy HH:mm:ss")): POST failed with status $($status)"
				}
			}
		}
}
Set-Alias -Name Watch-Presence -Value Watch-Presence-func -Description "$($Moniker): Watch for Teams presence changes"
