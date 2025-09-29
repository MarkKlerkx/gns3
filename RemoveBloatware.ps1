# --- HERSTELSCRIPT VOOR SYSprep APPX-VALIDATIEFOUTEN ---

Write-Host "Starten van het herstelscript om AppX-packages volledig op te schonen..." -ForegroundColor Cyan
Write-Host "Dit script probeert alle restanten te verwijderen van de apps uit het originele optimalisatiescript."

# Sla de huidige instelling voor de progress bar op
$OriginalProgressPreference = $ProgressPreference
# Schakel de progress bars tijdelijk uit om het 'hangen' van de console te voorkomen
$ProgressPreference = 'SilentlyContinue'

# Dit is de VOLLEDIGE lijst van apps uit het agressieve script
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

Write-Host "De volgende $(($BloatwareApps).Count) app-patronen worden gecontroleerd en opgeschoond:"
$BloatwareApps | ForEach-Object { Write-Host " - $_" }
Write-Host "------------------------------------------------------------"

foreach ($App in $BloatwareApps) {
    Write-Host "Controleren en opschonen van packages die overeenkomen met '$App'..." -ForegroundColor Yellow
    
    # STAP 1: Verwijder de package voor ALLE gebruikers. Dit is cruciaal.
    # We gebruiken -ErrorAction SilentlyContinue voor het geval de app al weg is.
    Get-AppxPackage -Name $App -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    
    # STAP 2: Verwijder de 'provisioned' versie. Dit voorkomt dat het terugkomt.
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $App } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

# Herstel de originele instelling voor de progress bar
$ProgressPreference = $OriginalProgressPreference

Write-Host "------------------------------------------------------------"
Write-Host "Herstelscript voltooid!" -ForegroundColor Green
Write-Host "Alle potentieel problematische AppX-packages zijn nu op de meest grondige manier verwijderd."
Write-Host "Probeer Sysprep nu opnieuw uit te voeren."
