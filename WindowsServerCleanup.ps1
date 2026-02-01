<#
.SYNOPSIS
    GNS3 Windows Server 2022 Optimization Script.
    Optimaliseert RAM, CPU en Disk footprint voor virtualisatie.
#>

# Check voor Admin
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Voer dit script uit als Administrator!"
    Exit
}

Write-Host "--- Start optimalisatie voor Windows Server 2022 ---" -ForegroundColor Green

# --- Sectie 1: Server Specifieke Services & Functies ---
Write-Host "Sectie 1: Services en Systeeminstellingen aanpassen..." -ForegroundColor Cyan

# Hibernation uit (bespaart GB's aan schijfruimte)
powercfg /h off

# Windows Update & Orchestrator (voorkomt onverwachte CPU pieken in GNS3)
$Services = @("wuauserv", "UsoSvc", "SysMain", "WSearch", "DiagTrack", "dmwappushservice")
foreach ($Svc in $Services) {
    Set-Service -Name $Svc -StartupType Disabled -ErrorAction SilentlyContinue
    Stop-Service -Name $Svc -Force -ErrorAction SilentlyContinue
    Write-Host "  - Service $Svc uitgeschakeld." -ForegroundColor Yellow
}

# Windows Defender verwijderen (optioneel, maar aanbevolen voor lab-performance)
# Verwijder de '#' hieronder als je Defender volledig wilt verwijderen:
# Uninstall-WindowsFeature -Name Windows-Defender

# --- Sectie 2: UI & Performance Tweaks ---
Write-Host "Sectie 2: Performance Tweaks toepassen..." -ForegroundColor Cyan

# Visuele effecten op 'Best Performance' (stelt VisualFXSetting in op 2)
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -Force

# Telemetry uitschakelen
$TelemetryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
if (-NOT (Test-Path $TelemetryPath)) { New-Item -Path $TelemetryPath -Force | Out-Null }
Set-ItemProperty -Path $TelemetryPath -Name "AllowTelemetry" -Value 0 -Type DWord -Force

# --- Sectie 3: Opschonen (Cruciaal voor kleine GNS3 Images) ---
Write-Host "Sectie 3: Deep Cleanup (WinSxS & Temp)..." -ForegroundColor Cyan

# Verwijder ongebruikte componenten en reset de basis (maakt updates permanent)
Write-Host "  - Bezig met DISM Cleanup (dit kan even duren)..." -ForegroundColor Yellow
DISM.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase

# CompactOS inschakelen (comprimeert de OS bestanden op de achtergrond)
Write-Host "  - CompactOS activeren..." -ForegroundColor Yellow
compact.exe /CompactOS:always

# Event logs legen
wevtutil.exe el | ForEach-Object { wevtutil.exe cl "$_" }

# --- Sectie 4: Zero-Fill voor GNS3/QCOW2 ---
Write-Host "Sectie 4: SDelete voorbereiding..." -ForegroundColor Cyan

$sdeletePath = Join-Path $env:TEMP "sdelete64.exe"
if (-not (Test-Path $sdeletePath)) {
    Write-Host "  - SDelete downloaden..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://live.sysinternals.com/sdelete64.exe" -OutFile $sdeletePath
}

Write-Host "  - SDelete voert zero-fill uit op C: (BELANGRIJK voor kleine VM's)..." -ForegroundColor Magenta
& $sdeletePath -accepteula -z C:

# Cleanup
Remove-Item -Path $sdeletePath -Force
Write-Host "--- Optimalisatie voltooid! ---" -ForegroundColor Green
Read-Host "Druk op Enter om af te sluiten..."
