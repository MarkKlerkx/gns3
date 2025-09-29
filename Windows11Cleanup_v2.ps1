<#
.SYNOPSIS
    This is the definitive, all-in-one script to aggressively optimize a Windows
    installation for use as a virtualization template. It includes a robust method
    for removing bloatware to prevent Sysprep validation errors.
    It must be run as an Administrator.
#>

# Step 0: Check for Administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script must be run as an Administrator."
    Read-Host "Press Enter to exit."
    Exit
}

# Start of the script
Write-Host "Starting the Definitive Windows Optimization Script..." -ForegroundColor Green
Write-Host "======================================================="

# --- Section 1: System Tweaks & Service Disabling ---
Write-Host "Section 1: Applying System Tweaks and Disabling Services" -ForegroundColor Cyan

# Step 1.1: Disable Hibernation
Write-Host "  - Step 1.1: Disabling Hibernation..." -ForegroundColor Yellow
powercfg /h off

# Step 1.2: Set a fixed Page File size
Write-Host "  - Step 1.2: Setting Page File to a fixed size of 1024 MB..." -ForegroundColor Yellow
$ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
$ComputerSystem.AutomaticManagedPagefile = $false
Set-CimInstance -InputObject $ComputerSystem
$PageFile = Get-CimInstance -ClassName Win32_PageFileSetting | Select-Object -First 1
if ($PageFile) { Set-CimInstance -InputObject $PageFile -Property @{InitialSize = 1024; MaximumSize = 1024} } 
else { Set-CimInstance -ClassName Win32_PageFileSetting -Property @{Name="C:\pagefile.sys"; InitialSize = 1024; MaximumSize = 1024} }

# Step 1.3: Disable System Restore
Write-Host "  - Step 1.3: Disabling System Restore..." -ForegroundColor Yellow
Disable-ComputerRestore -Drive "C:\"

# Step 1.4: Disable Core Unnecessary Services
Write-Host "  - Step 1.4: Disabling core unnecessary services (Updates, Search, SysMain)..." -ForegroundColor Yellow
Set-Service -Name wuauserv -StartupType Disabled; Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Set-Service -Name SysMain -StartupType Disabled; Stop-Service -Name SysMain -Force -ErrorAction SilentlyContinue
Set-Service -Name WSearch -StartupType Disabled; Stop-Service -Name WSearch -Force -ErrorAction SilentlyContinue

# Step 1.5: Disable Telemetry and Diagnostics Services
Write-Host "  - Step 1.5: Disabling Telemetry and Diagnostics services..." -ForegroundColor Yellow
Set-Service -Name DiagTrack -StartupType Disabled; Stop-Service -Name DiagTrack -Force -ErrorAction SilentlyContinue
Set-Service -Name dmwappushservice -StartupType Disabled; Stop-Service -Name dmwappushservice -Force -ErrorAction SilentlyContinue

# Step 1.6: Disable Windows Defender
Write-Host "  - Step 1.6: Disabling Windows Defender..." -ForegroundColor Yellow
$DefenderRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
if (-NOT (Test-Path $DefenderRegPath)) { New-Item -Path $DefenderRegPath -Force | Out-Null }
Set-ItemProperty -Path $DefenderRegPath -Name DisableAntiSpyware -Value 1 -Type DWord -Force
try { Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop } catch { Write-Warning "Could not disable real-time monitoring. Tamper Protection may be enabled." }

# Step 1.7: Apply Registry Tweaks
Write-Host "  - Step 1.7: Applying Registry Tweaks for performance and privacy..." -ForegroundColor Yellow
$TelemetryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
if (-NOT (Test-Path $TelemetryPath)) { New-Item -Path $TelemetryPath -Force | Out-Null }
Set-ItemProperty -Path $TelemetryPath -Name "AllowTelemetry" -Value 0 -Type DWord -Force
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -Force
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-310093Enabled" -Value 0 -Force

# Step 1.8: Disable Unnecessary Scheduled Tasks
Write-Host "  - Step 1.8: Disabling unnecessary Scheduled Tasks..." -ForegroundColor Yellow
Get-ScheduledTask -TaskName 'ScheduledDefrag' | Disable-ScheduledTask -ErrorAction SilentlyContinue
Get-ScheduledTask -TaskPath "\Microsoft\Windows\Customer Experience Improvement Program\*" | Disable-ScheduledTask -ErrorAction SilentlyContinue
Get-ScheduledTask -TaskPath "\Microsoft\Windows\Application Experience\*" | Disable-ScheduledTask -ErrorAction SilentlyContinue
Get-ScheduledTask -TaskPath "\Microsoft\Windows\DiskDiagnostic\*" | Disable-ScheduledTask -ErrorAction SilentlyContinue

# --- Section 2: Robust Bloatware Removal ---
Write-Host "Section 2: Performing Robust Bloatware Removal" -ForegroundColor Cyan

# Step 2.1: Thoroughly remove built-in 'Bloatware' Apps
$OriginalProgressPreference = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'

Write-Host "  - Step 2.1: Thoroughly removing built-in 'Bloatware' Apps to prevent Sysprep errors..." -ForegroundColor Yellow

$BloatwareApps = @(
    "Microsoft.549981C3F5F10", "Microsoft.BingNews", "Microsoft.BingWeather", 
    "Microsoft.GetHelp", "Microsoft.Getstarted", "Microsoft.Microsoft3DViewer", 
    "Microsoft.MicrosoftOfficeHub", "Microsoft.MicrosoftSolitaireCollection", 
    "Microsoft.MixedReality.Portal", "Microsoft.Office.OneNote", "Microsoft.People", 
    "Microsoft.Print3D", "Microsoft.SkypeApp", "Microsoft.ScreenSketch", "Microsoft.Wallet", 
    "Microsoft.WindowsAlarms", "Microsoft.WindowsCommunicationsApps", 
    "Microsoft.WindowsFeedbackHub", "Microsoft.WindowsMaps", "Microsoft.WindowsSoundRecorder", 
    "Microsoft.Xbox.*", "Microsoft.YourPhone", "Microsoft.ZuneMusic", "Microsoft.ZuneVideo"
)

foreach ($App in $BloatwareApps) {
    Write-Host "    - Thoroughly cleaning package matching '$App'..." -ForegroundColor Gray
    # Force removal for all users
    Get-AppxPackage -Name $App -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    # Force removal of the provisioned package
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $App } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

$ProgressPreference = $OriginalProgressPreference
Write-Host "  - Robust bloatware removal process completed." -ForegroundColor Green


# --- Section 3: Deep System & File Cleanup ---
Write-Host "Section 3: Performing Deep System and File Cleanup" -ForegroundColor Cyan

# Step 3.1: Clear Caches and Temp Files
Write-Host "  - Step 3.1: Clearing all caches and temp files..." -ForegroundColor Yellow
Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue

# Step 3.2: Clean up Component Store (WinSxS) with DISM
Write-Host "  - Step 3.2: Cleaning up the Component Store (WinSxS) with DISM (this may take a while)..." -ForegroundColor Yellow
DISM.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase

# Step 3.3: Enable CompactOS
Write-Host "  - Step 3.3: Enabling CompactOS to compress system files..." -ForegroundColor Yellow
compact.exe /CompactOS:always

# Step 3.4: Final Cleanup Actions
Write-Host "  - Step 3.4: Performing final cleanup actions (Event Logs, DNS, Recycle Bin)..." -ForegroundColor Yellow
wevtutil.exe el | ForEach-Object { wevtutil.exe cl "$_" }
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
Clear-DnsClientCache


# --- Section 4: Finalization with SDelete ---
Write-Host "Section 4: Zero-filling free space for optimal VM performance" -ForegroundColor Cyan

# Step 4.1: Download SDelete
Write-Host "  - Step 4.1: Downloading SDelete from GitHub..." -ForegroundColor Yellow
$sdeleteUrl = "https://raw.githubusercontent.com/MarkKlerkx/gns3/main/sdelete64.exe"
$sdeletePath = Join-Path $env:TEMP "sdelete64.exe"
try {
    Invoke-WebRequest -Uri $sdeleteUrl -OutFile $sdeletePath -ErrorAction Stop
    Write-Host "    SDelete downloaded successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to download SDelete. Please check the URL and your internet connection."
    Read-Host "Press Enter to exit."
    Exit
}

# Step 4.2: Run SDelete
Write-Host "  - Step 4.2: Running SDelete to zero-fill free space. THIS WILL TAKE A LONG TIME." -ForegroundColor Magenta
& $sdeletePath -accepteula -z C:

# Step 4.3: Clean up SDelete executable
Write-Host "  - Step 4.3: Cleaning up SDelete..." -ForegroundColor Yellow
Remove-Item -Path $sdeletePath -Force


# --- Completion ---
Write-Host "======================================================="
Write-Host "DEFINITIVE optimization complete!" -ForegroundColor Green
Write-Host "The system is now prepared for Sysprep."
Read-Host "Press Enter to close this window."
