Write-Host "# Installing PowerShell 7.4 (if not already installed)"

$ErrorActionPreference = 'Stop'
$ConfirmPreference     = 'None'
$ProgressPreference    = 'SilentlyContinue'

# ------------------------------
# Check if pwsh already exists
# ------------------------------
if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    $v = & pwsh -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'
    Write-Host "PowerShell already installed: $v"
    exit 0
}

# ------------------------------
# Install PS7 (Chocolatey example)
# ------------------------------
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: choco not found"
    exit 1
}

Write-Host "Installing PowerShell 7.4..."
choco install powershell-core --version=7.4.0 -y --no-progress

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: choco failed installing PowerShell 7.4 (exit $LASTEXITCODE)"
    exit 1
}

# ------------------------------
# Verify
# ------------------------------
if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    & pwsh -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'
    exit 0
}

Write-Host "ERROR: pwsh not found after install"
exit 1
