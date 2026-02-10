Write-Host "# Installing Bruno API Tool (if not already installed)"

$ErrorActionPreference = 'Stop'
$ConfirmPreference     = 'None'

# ------------------------------
# Check if Bruno already exists
# ------------------------------
if (Get-Command bruno -ErrorAction SilentlyContinue) {
    Write-Host "Bruno already installed:"
    bruno --version
    exit 0
}

# ------------------------------
# Ensure winget is available
# ------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: winget not found. Install 'App Installer' from Microsoft Store (or ensure winget is present)."
    exit 1
}

# ------------------------------
# Install Bruno
# ------------------------------
Write-Host "Installing Bruno..."
winget install --id Bruno.Bruno -e --accept-source-agreements --accept-package-agreements

# ------------------------------
# Ensure Bruno is on PATH (best-effort)
# ------------------------------
$brunoPath = "$env:LOCALAPPDATA\Programs\Bruno"

if (Test-Path $brunoPath -and ($env:Path -notlike "*$brunoPath*")) {
    $env:Path += ";$brunoPath"

    # Persist for future shells (Machine PATH used to match your style)
    [Environment]::SetEnvironmentVariable(
            "Path",
            [Environment]::GetEnvironmentVariable("Path", "Machine") + ";$brunoPath",
            [EnvironmentVariableTarget]::Machine
    )
}

# ------------------------------
# Verify (try current shell, then fallback to expected install path)
# ------------------------------
if (Get-Command bruno -ErrorAction SilentlyContinue) {
    bruno --version
    exit 0
}

$brunoExe = Join-Path $brunoPath "bruno.exe"
if (Test-Path $brunoExe) {
    & $brunoExe --version
    exit 0
}

Write-Host "ERROR: Bruno install finished but 'bruno' was not found on PATH."
exit 1
