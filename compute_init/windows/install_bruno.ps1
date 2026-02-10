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
# Install via winget if available
# ------------------------------
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "Installing Bruno via winget..."
    winget install --id Bruno.Bruno -e --accept-source-agreements --accept-package-agreements

    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARN: winget failed (exit $LASTEXITCODE). Will try Chocolatey..."
    } else {
        # Best-effort verify
        if (Get-Command bruno -ErrorAction SilentlyContinue) {
            bruno --version
            exit 0
        }

        $brunoExe = Join-Path "$env:LOCALAPPDATA\Programs\Bruno" "bruno.exe"
        if (Test-Path $brunoExe) {
            & $brunoExe --version
            exit 0
        }

        Write-Host "WARN: winget reported success but Bruno not found. Will try Chocolatey..."
    }
}

# ------------------------------
# Install via Chocolatey
# ------------------------------
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Neither winget nor Chocolatey are available. Install one of them first."
    exit 1
}

Write-Host "Installing Bruno via Chocolatey..."
choco install bruno -y --no-progress

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Chocolatey failed installing Bruno (exit $LASTEXITCODE)"
    exit 1
}

# ------------------------------
# Verify
# ------------------------------
if (Get-Command bruno -ErrorAction SilentlyContinue) {
    bruno --version
    exit 0
}

# Common choco install locations (best-effort)
$maybe = @(
    "C:\ProgramData\chocolatey\bin\bruno.exe",
    "C:\Program Files\Bruno\bruno.exe",
    "$env:LOCALAPPDATA\Programs\Bruno\bruno.exe"
)

foreach ($p in $maybe) {
    if (Test-Path $p) {
        & $p --version
        exit 0
    }
}

Write-Host "ERROR: Bruno install completed but bruno.exe was not found."
exit 1
