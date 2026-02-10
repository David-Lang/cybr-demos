Write-Host "# Installing NuGet (if not already installed)"

$ErrorActionPreference = 'Stop'
$ConfirmPreference     = 'None'

$nugetDir  = "C:\ProgramData\NuGet"
$nugetExe  = "$nugetDir\nuget.exe"
$pathEntry = $nugetDir

# ------------------------------
# Check if NuGet already exists
# ------------------------------
if (Get-Command nuget.exe -ErrorAction SilentlyContinue) {
    Write-Host "NuGet already installed:"
    nuget.exe help | Select-Object -First 1
    return
}

# ------------------------------
# Prep directory
# ------------------------------
New-Item -ItemType Directory -Path $nugetDir -Force | Out-Null

# ------------------------------
# Download NuGet
# ------------------------------
Write-Host "Downloading NuGet..."
Invoke-WebRequest `
    -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" `
    -OutFile $nugetExe

# ------------------------------
# Ensure NuGet is on PATH
# ------------------------------
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")

if ($machinePath -notlike "*$pathEntry*") {
    [Environment]::SetEnvironmentVariable(
            "Path",
            "$machinePath;$pathEntry",
            [EnvironmentVariableTarget]::Machine
    )
    $env:Path += ";$pathEntry"
}

# ------------------------------
# Verify
# ------------------------------
nuget.exe help | Select-Object -First 1

exit 0
