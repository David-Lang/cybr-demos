Write-Host "# Installing Git (if not already installed)"

$ErrorActionPreference = 'Stop'
$ConfirmPreference     = 'None'

# ------------------------------
# Check if Git already exists
# ------------------------------
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "Git already installed:"
    git --version
    exit 0
}

# ------------------------------
# Install Git
# ------------------------------
Write-Host "Installing Git..."
choco install git -y --no-progress

# ------------------------------
# Ensure Git is on PATH
# ------------------------------
$gitPath = "C:\Program Files\Git\cmd"

if ($env:Path -notlike "*$gitPath*") {
    $env:Path += ";$gitPath"

    [Environment]::SetEnvironmentVariable(
            "Path",
            [Environment]::GetEnvironmentVariable("Path", "Machine") + ";$gitPath",
            [EnvironmentVariableTarget]::Machine
    )
}

# ------------------------------
# Verify
# ------------------------------
git --version
