# One-time signing setup. Run on the owner's Windows PC, not a CI runner.
$ErrorActionPreference = 'Stop'
$repo = 'pilialvu75-hue/AIVEXUS-RendezVous'
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) { throw 'GitHub CLI non trovato. Installare con winget install --id GitHub.cli -e e riaprire PowerShell.' }
gh auth status
if ($LASTEXITCODE -ne 0) { throw 'Eseguire gh auth login prima di continuare.' }
$keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytool) {
    $candidates = @("$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe")
    if ($env:JAVA_HOME) { $candidates += "$env:JAVA_HOME\bin\keytool.exe" }
    $keytool = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $keytool) { throw 'Java keytool non trovato. Installare JDK 17 o Android Studio.' }
$folder = Join-Path $env:LOCALAPPDATA 'AIVEXUS\Signing\RendezVous'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$key = Join-Path $folder 'rendezvous-release.p12'
$secure = Read-Host 'Password della chiave (almeno 16 caratteri; conservala nel tuo gestore password)' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $env:RV_KEY_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    if ($env:RV_KEY_PASSWORD.Length -lt 16) { throw 'Password troppo breve.' }
    if (!(Test-Path $key)) {
        & $keytool -genkeypair -storetype PKCS12 -keystore $key -storepass:env RV_KEY_PASSWORD -keypass:env RV_KEY_PASSWORD -alias rendezvous -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=AIVEXUS RendezVous'
        if ($LASTEXITCODE -ne 0) { throw 'Creazione chiave fallita.' }
    }
    $cer = Join-Path $folder 'public-cert.der'
    & $keytool -exportcert -keystore $key -storepass:env RV_KEY_PASSWORD -alias rendezvous -file $cer
    if ($LASTEXITCODE -ne 0) { throw 'Password o chiave non valida.' }
    $fingerprint = (Get-FileHash $cer -Algorithm SHA256).Hash.ToLowerInvariant()
    # Preserve the previously pinned identity on rerun; do not overwrite it silently.
    $existing = gh variable list --repo $repo --json name,value
    if ($LASTEXITCODE -ne 0) { throw 'Impossibile leggere le variabili del repository.' }
    $old = ($existing | ConvertFrom-Json | Where-Object { $_.name -eq 'RV_SIGNER_SHA256' }).value
    if ($old -and $old -ne $fingerprint) { throw 'Fingerprint differente da quello registrato: interrompere e recuperare la chiave originale.' }
    Write-Host "Fingerprint pubblico: $fingerprint"
    Write-Host "Chiave salvata in: $key"
    Write-Host 'Copia il file .p12 in un secondo supporto privato e conserva la password separatamente. Non caricare il file nel repository.'
    if ((Read-Host 'Hai salvato la copia di sicurezza? Scrivi SI per configurare GitHub') -ne 'SI') { throw 'Configurazione interrotta; la chiave locale resta disponibile.' }
    [Convert]::ToBase64String([IO.File]::ReadAllBytes($key)) | gh secret set RV_KEYSTORE_B64 --repo $repo
    if ($LASTEXITCODE -ne 0) { throw 'Caricamento secret keystore fallito.' }
    $env:RV_KEY_PASSWORD | gh secret set RV_KEY_PASSWORD --repo $repo
    if ($LASTEXITCODE -ne 0) { throw 'Caricamento secret password fallito.' }
    gh variable set RV_SIGNER_SHA256 --repo $repo --body $fingerprint
    if ($LASTEXITCODE -ne 0) { throw 'Configurazione fingerprint fallita.' }
    Write-Host 'Configurazione completata. Non inviare chiave o password in chat.'
} finally {
    Remove-Item Env:RV_KEY_PASSWORD -ErrorAction SilentlyContinue
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    $secure.Dispose()
}
