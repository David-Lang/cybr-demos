# Automated Summon Installer for Windows (PowerShell Script)

Write-Host "Starting Summon installation..."

# Define URL for the latest release of Summon for Windows
$releaseUrl = "https://github.com/cyberark/summon/releases/latest/download/summon-windows-amd64.zip"

# Define installation directory
$installDir = "C:\Program Files\summon"

# Create a temporary directory for downloading
$tempDir = [System.IO.Path]::GetTempPath()
$tempFile = Join-Path $tempDir "summon.zip"

# Download the archive
Write-Host "Downloading Summon..."
Invoke-WebRequest -Uri $releaseUrl -OutFile $tempFile

# Create the installation directory if it doesn't exist
if (-Not (Test-Path -Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir
}

# Extract the archive
Write-Host "Extracting Summon..."
Expand-Archive -Path $tempFile -DestinationPath $installDir -Force

# Clean up the temporary file
Remove-Item -Path $tempFile

# Add the install directory to the PATH
$currentPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($currentPath -notlike "*$installDir*") {
    [System.Environment]::SetEnvironmentVariable("Path", "$currentPath;$installDir", "Machine")
    Write-Host "The installation directory has been added to the system PATH."
} else {
    Write-Host "The installation directory is already in the system PATH."
}

Write-Host "Summon installed successfully to $installDir."

# Install Conjur Provider by building from source
Write-Host "Starting Conjur provider installation..."

# Check if Go is installed
$goVersion = $null
try {
    $goVersion = & go version 2>$null
} catch {
    Write-Host "Go is not installed. Installing Go..."

    # Define Go download URL (latest stable version)
    $goDownloadUrl = "https://go.dev/dl/go1.22.0.windows-amd64.msi"
    $goInstallerPath = Join-Path $tempDir "go-installer.msi"

    # Download Go installer
    Write-Host "Downloading Go installer..."
    Invoke-WebRequest -Uri $goDownloadUrl -OutFile $goInstallerPath

    # Install Go silently
    Write-Host "Installing Go (this may take a few minutes)..."
    Start-Process msiexec.exe -ArgumentList "/i", $goInstallerPath, "/quiet", "/norestart" -Wait -NoNewWindow

    # Clean up installer
    Remove-Item -Path $goInstallerPath -Force

    # Refresh environment variables to pick up Go installation
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Verify Go installation
    try {
        $goVersion = & go version 2>$null
        Write-Host "Go installed successfully: $goVersion"
    } catch {
        Write-Host "Error: Go installation failed. Please install Go manually from https://golang.org/dl/"
        Write-Host "Skipping Conjur provider installation."
        return
    }
}

if (-not $goVersion) {
    try {
        $goVersion = & go version 2>$null
    } catch {
        Write-Host "Error: Go is still not available. Please restart your PowerShell session."
        Write-Host "Skipping Conjur provider installation."
        return
    }
}

Write-Host "Go detected: $goVersion"

# Define provider installation directory
$providerDir = "$installDir\Providers"

# Create provider directory if it doesn't exist
if (-Not (Test-Path -Path $providerDir)) {
    New-Item -ItemType Directory -Path $providerDir
}

# Create a temporary build directory
$buildDir = Join-Path $tempDir "summon-conjur-build"
if (Test-Path -Path $buildDir) {
    Remove-Item -Path $buildDir -Recurse -Force
}
New-Item -ItemType Directory -Path $buildDir | Out-Null

# Clone the summon-conjur repository
Write-Host "Cloning summon-conjur repository..."
$cloneResult = & git clone https://github.com/cyberark/summon-conjur.git $buildDir 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to clone repository. Make sure Git is installed."
    Write-Host "Skipping Conjur provider installation."
    Remove-Item -Path $buildDir -Recurse -Force -ErrorAction SilentlyContinue
    return
}

# Build the provider
Write-Host "Building Conjur provider from source..."
Push-Location $buildDir
try {
    # Build for Windows
    $env:GOOS = "windows"
    $env:GOARCH = "amd64"
    $buildOutput = & go build -o "$providerDir\summon-conjur.exe" ./cmd/main.go 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Conjur provider built successfully!"
        Write-Host "Executable location: $providerDir\summon-conjur.exe"
    } else {
        Write-Host "Error building Conjur provider:"
        Write-Host $buildOutput
    }
} finally {
    Pop-Location
}

# Clean up build directory
Remove-Item -Path $buildDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Conjur provider installation completed."

# Refresh PATH in current session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Get the parent directory (powershell folder)
$scriptDir = Split-Path -Parent $PSScriptRoot

# Unblock PowerShell scripts
Unblock-File -Path "$scriptDir\configure.ps1" -ErrorAction SilentlyContinue
Unblock-File -Path "$scriptDir\demo.ps1" -ErrorAction SilentlyContinue
Unblock-File -Path "$scriptDir\consumer.ps1" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Installation complete!"
Write-Host ""

# Run configure.ps1 to set up Conjur environment variables
Write-Host "Running configuration script to set up Conjur environment variables..."
Write-Host ""
& "$scriptDir\configure.ps1"

Write-Host ""
Write-Host "Setup complete! You can now run the demo with: .\demo.ps1"
