## GNS3 Maintenance Scripts

The following scripts can be executed with following commands:

-   vmSize.sh
-   W10TemplateFTPv5.sh
-   setup_gns3_backup.sh
-   gns3_restore.sh
-   gns3_monitor.sh
-   UbuntuCleanup.sh

In the commands below, replace ***name_script.sh*** with the name of the real script.

sudo curl -sSL  [https://raw.githubusercontent.com/MarkKlerkx/gns3/main/name_script.sh](https://raw.githubusercontent.com/MarkKlerkx/gns3/main/name_script.sh)  -o /tmp/***name_script.sh*** 

sudo chmod +x /tmp/***name_script.sh*** 

sudo bash /tmp/***name_script.sh***

## GNS3 - Windows 10 Silent Template

 - Install Windows 10 with the default settings
 - Options:
	 - Set up for personal use
	 - Offline account
	 - Limited experience
	 - Customize experience: Skip
 - Open Powershell ISE with "*Open as Administrator*"
 - Go to the Github page of this tutorial and copy and execute the following PowerShell commands:
	 - Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force 
	 - Invoke-WebRequest -Uri "https://raw.githubusercontent.com/MarkKlerkx/gns3/main/Windows11Cleanup.ps1" -OutFile "$env:TEMP\Windows11Cleanup.ps1"
	 - & "$env:TEMP\Windows11Cleanup.ps1"
	- C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
 - Logon to the console of the GNS3 server and browse to the location of the linked clone file of the template VM. The folder is located in /opt/gns3/projects/***project_id***/project-files/***vm_id***/.
 - Execute the following command to convert the linked image to a GNS3 template:
	 - sudo qemu-img convert -O qcow2 hda_disk.qcow2 /opt/gns3/images/QEMU/***NameTemplate.qcow2***
  - Create a template in GNS3 to test this template.
