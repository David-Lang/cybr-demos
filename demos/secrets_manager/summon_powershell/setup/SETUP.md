# Summon Automated Setup Guide for Windows

This guide explains how to use the automated setup script to install Summon and the Conjur provider on Windows.

## Overview

The `setup.ps1` script provides a fully automated installation process that:

1. Downloads and installs **Summon** for Windows
2. Installs **Go** (if not already installed)
3. Clones and builds the **Conjur provider** from source
4. Configures the system **PATH** automatically
5. Sets up the proper directory structure

## Prerequisites

### Required
- **Windows 10 or later** (for tar command support)
- **PowerShell 5.1 or later**
- **Administrator privileges** (required for installing to Program Files)
- **Internet connection** (for downloading components)

### Automatically Installed by Script
- **Go** (downloaded and installed if not present)
- **Summon** (downloaded from official releases)
- **Conjur Provider** (built from source)

### Must Be Installed Manually
- **Git** - Download from [https://git-scm.com/download/win](https://git-scm.com/download/win)
  - Required for cloning the Conjur provider repository
  - Verify installation: `git --version`

## Installation Steps

### 1. Open PowerShell as Administrator

Right-click on PowerShell and select "Run as Administrator"

### 2. Navigate to the PowerShell Directory

```powershell
cd path\to\summon\powershell
```

### 3. Run the Setup Script

```powershell
.\setup.ps1
```

### 4. Wait for Installation to Complete

The script will display progress messages:
```
Starting Summon installation...
Downloading Summon...
Extracting Summon...
The installation directory has been added to the system PATH.
Summon installed successfully to C:\Program Files\summon.

Starting Conjur provider installation...
Go detected: go version go1.22.0 windows/amd64
Cloning summon-conjur repository...
Building Conjur provider from source...
Conjur provider built successfully!
Executable location: C:\Program Files\summon\Providers\summon-conjur.exe

Installation complete! Please restart your PowerShell session to use summon.
```

### 5. Restart PowerShell

Close and reopen your PowerShell session to refresh the PATH environment variable.

### 6. Verify Installation

```powershell
summon --version
```

You should see output similar to:
```
summon version 0.10.10
```

## What Gets Installed

### Installation Directory Structure

```
C:\Program Files\summon\
├── summon.exe                    # Main Summon executable
└── Providers\
    └── summon-conjur.exe        # Conjur provider executable
```

### System Changes

1. **System PATH** - `C:\Program Files\summon` is added to the system PATH
2. **Go Installation** - If Go wasn't installed, it's added to `C:\Program Files\Go` (default)
3. **Environment Variables** - PATH is updated to include both Summon and Go directories

## Installation Details

### Summon Installation

- **Source**: GitHub releases (latest version)
- **URL**: `https://github.com/cyberark/summon/releases/latest/download/summon-windows-amd64.zip`
- **Location**: `C:\Program Files\summon\summon.exe`

### Go Installation

- **Version**: Go 1.22.0
- **URL**: `https://go.dev/dl/go1.22.0.windows-amd64.msi`
- **Installation**: Silent MSI installation
- **Only installed if**: Go is not already present on the system

### Conjur Provider Build

- **Source**: Built from GitHub source code
- **Repository**: `https://github.com/cyberark/summon-conjur`
- **Build Process**: 
  1. Clone repository to temporary directory
  2. Build with `go build` for Windows/AMD64
  3. Output to `C:\Program Files\summon\Providers\summon-conjur.exe`
  4. Clean up temporary files

## Troubleshooting

### Error: Access Denied

**Problem**: Permission denied when installing to Program Files

**Solution**: Run PowerShell as Administrator

```powershell
# Right-click PowerShell → Run as Administrator
```

### Error: Git Not Found

**Problem**: Script fails when trying to clone repository

**Solution**: Install Git manually

1. Download Git from [https://git-scm.com/download/win](https://git-scm.com/download/win)
2. Install with default options
3. Restart PowerShell and run `setup.ps1` again

### Error: Go Installation Failed

**Problem**: Go installation doesn't complete successfully

**Solution**: Install Go manually

1. Download Go from [https://golang.org/dl/](https://golang.org/dl/)
2. Install the MSI package
3. Restart PowerShell and run `setup.ps1` again

### Error: Build Failed

**Problem**: Conjur provider build fails

**Common Causes**:
- Network connectivity issues during dependency download
- Go GOPATH or GOROOT not set correctly
- Antivirus blocking build process

**Solution**:

1. Check Go environment:
   ```powershell
   go env GOPATH
   go env GOROOT
   ```

2. Try building manually:
   ```powershell
   git clone https://github.com/cyberark/summon-conjur.git
   cd summon-conjur
   go build -o summon-conjur.exe ./cmd/main.go
   ```

3. Copy manually to Providers directory:
   ```powershell
   Copy-Item summon-conjur.exe "C:\Program Files\summon\Providers\"
   ```

### Summon Command Not Found After Installation

**Problem**: Running `summon` returns "command not found"

**Solutions**:

1. **Restart PowerShell** - PATH changes require a new session
   ```powershell
   # Close and reopen PowerShell
   ```

2. **Manually refresh PATH** in current session:
   ```powershell
   $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
   ```

3. **Verify PATH** includes Summon directory:
   ```powershell
   $env:Path -split ';' | Select-String summon
   ```

### Provider Not Found

**Problem**: Summon can't find the Conjur provider

**Solution**: Verify provider location

```powershell
# Check if provider exists
Test-Path "C:\Program Files\summon\Providers\summon-conjur.exe"

# Summon looks for providers in:
# 1. C:\Program Files\summon\Providers\
# 2. %USERPROFILE%\.summon\Providers\
# 3. Directories in PATH
```

## Verification Steps

After installation, verify everything is working:

### 1. Check Summon Version

```powershell
summon --version
```

### 2. List Available Providers

```powershell
summon --list-providers
```

Expected output:
```
Available providers:
- summon-conjur (C:\Program Files\summon\Providers\summon-conjur.exe)
```

### 3. Check Provider Version

```powershell
& "C:\Program Files\summon\Providers\summon-conjur.exe" --version
```

### 4. Verify Go Installation

```powershell
go version
```

## Updating Components

### Update Summon

Re-run the setup script - it will download and install the latest version:

```powershell
.\setup.ps1
```

### Update Conjur Provider

The setup script rebuilds the provider from the latest source each time it runs.

### Update Go

If you need a specific Go version, modify the `setup.ps1` file:

```powershell
# Change this line to your desired version:
$goDownloadUrl = "https://go.dev/dl/go1.XX.X.windows-amd64.msi"
```

## Uninstalling

To remove Summon and the Conjur provider:

### 1. Remove Installation Directory

```powershell
Remove-Item -Path "C:\Program Files\summon" -Recurse -Force
```

### 2. Remove from PATH

```powershell
$currentPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$newPath = ($currentPath -split ';' | Where-Object { $_ -ne "C:\Program Files\summon" }) -join ';'
[System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
```

### 3. (Optional) Uninstall Go

If you don't need Go for other projects:
1. Open "Add or Remove Programs"
2. Find "Go Programming Language"
3. Click Uninstall

## Next Steps

After successful installation:

1. **Configure Conjur Connection** - Set environment variables:
   ```powershell
   .\setEnvVars.ps1
   ```

2. **Test the Demo** - Run the sample application:
   ```powershell
   .\demo.ps1
   ```

3. **Read the Main README** - For usage instructions and examples:
   ```powershell
   Get-Content README.md
   ```

## Advanced Configuration

### Custom Installation Directory

To install to a different directory, modify `setup.ps1`:

```powershell
# Change this line:
$installDir = "C:\Program Files\summon"

# To:
$installDir = "C:\your\custom\path"
```

### Corporate Proxy Configuration

If behind a corporate proxy, configure before running setup:

```powershell
# Set proxy for PowerShell
$env:HTTP_PROXY = "http://proxy.example.com:8080"
$env:HTTPS_PROXY = "http://proxy.example.com:8080"

# Set proxy for Git
git config --global http.proxy http://proxy.example.com:8080
git config --global https.proxy http://proxy.example.com:8080

# Set proxy for Go
$env:GOPROXY = "http://proxy.example.com:8080"
```

### Silent Installation for Automation

The setup script already runs silently. For CI/CD integration:

```powershell
# Run setup and check exit code
.\setup.ps1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Setup failed"
    exit 1
}
```

## Support

For issues and questions:

- **Summon**: [https://github.com/cyberark/summon](https://github.com/cyberark/summon)
- **Conjur Provider**: [https://github.com/cyberark/summon-conjur](https://github.com/cyberark/summon-conjur)
- **CyberArk Documentation**: [https://cyberark.github.io/summon/](https://cyberark.github.io/summon/)

## Summary

The automated setup script simplifies Summon installation on Windows by:
- ✅ Handling all downloads automatically
- ✅ Installing dependencies (Go)
- ✅ Building the Conjur provider from source
- ✅ Configuring system PATH
- ✅ Requiring minimal user interaction

Just run as Administrator and let the script do the work!