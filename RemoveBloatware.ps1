# --- Section 2: Component & Bloatware Removal (VEILIGERE VERSIE) ---
Write-Host "Section 2: Removing Unnecessary Components (Safer Version)" -ForegroundColor Cyan

# Step 2.1: Remove built-in 'Bloatware' Apps
$OriginalProgressPreference = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'

Write-Host "  - Step 2.1: Removing a safer list of built-in 'Bloatware' Apps..." -ForegroundColor Yellow

# LIJST ZONDER BEKENDE PROBLEEM-APPS ZOALS CORTANA
$BloatwareApps = @(
    "Microsoft.BingNews", "Microsoft.BingWeather", "Microsoft.GetHelp", "Microsoft.Getstarted",
    "Microsoft.Microsoft3DViewer", "Microsoft.MicrosoftOfficeHub", "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.MixedReality.Portal", "Microsoft.Office.OneNote", "Microsoft.People",
    "Microsoft.Print3D", "Microsoft.SkypeApp", "Microsoft.ScreenSketch", "Microsoft.Wallet",
    "Microsoft.WindowsAlarms", "Microsoft.WindowsCommunicationsApps", "Microsoft.WindowsFeedbackHub",
    "Microsoft.WindowsMaps", "Microsoft.WindowsSoundRecorder", "Microsoft.Xbox.*",
    "Microsoft.YourPhone", "Microsoft.ZuneMusic", "Microsoft.ZuneVideo"
)

foreach ($App in $BloatwareApps) {
    Write-Host "    - Attempting to remove package matching '$App'..." -ForegroundColor Gray
    Get-AppxPackage -AllUsers -Name $App | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $App } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

$ProgressPreference = $OriginalProgressPreference
Write-Host "  - Bloatware removal process completed." -ForegroundColor Green
