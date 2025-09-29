## GNS3 - Windows 10 Silent Template

 - Install Windows 10 with the default settings
 - Options:
	 - Set up for personal use
	 - Offline account
	 - Limited experience
	 - Customize experience: Skip
 - Open Powershell ISE with "*Open as Administrator*"
 - Execute the following commands in Powershell:
	 - Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force 
	 - Invoke-WebRequest -Uri "https://raw.githubusercontent.com/MarkKlerkx/gns3/main/Windows11Cleanup.ps1" -OutFile "$env:TEMP\Windows11Cleanup.ps1"
	 - & "$env:TEMP\Windows11Cleanup.ps1"
