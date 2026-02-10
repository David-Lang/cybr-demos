# compute_init\windows\user_setup.ps1
# Runs in an INTERACTIVE user session (Administrator logon).
# Do NOT run as SYSTEM. Intended for taskbar pins / Explorer / HKCU changes.
# Idempotent via marker file.

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$BootstrapDir = "C:\bootstrap"
$LogDir       = "$BootstrapDir\logs"
$MarkerFile   = "$BootstrapDir\user_setup.completed"
$StartedFile  = "$BootstrapDir\user_setup.started"
$LogFile      = "$LogDir\user_setup_log.txt"

New-Item -ItemType Directory -Path $BootstrapDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
New-Item -ItemType File -Path $StartedFile -Force | Out-Null

Start-Transcript -Append $LogFile | Out-Null
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$ts $Message"
}

try {
    if (Test-Path $MarkerFile) {
        Write-Log "user_setup already completed. Exiting."
        Stop-Transcript | Out-Null
        exit 0
    }

    Write-Log "# Running user setup (interactive)"

    # Import your existing pin module
    $PinModule = Join-Path $ScriptRoot "module_pin_to_taskbar.psm1"
    if (-not (Test-Path $PinModule)) { throw "Missing pin module: $PinModule" }

    Import-Module $PinModule -Force

    Write-Log "# Pinning apps to taskbar (best-effort)"
    # Best-effort: pin failures shouldn't kill the whole setup
    $pins = @(
        "C:\Windows\notepad.exe",
        "C:\Windows\explorer.exe",
        "C:\Program Files (x86)\Notepad++\notepad++.exe",
        "C:\Program Files\Google\Chrome\Application\Chrome.exe",
        "C:\Windows\System32\WindowsPowerShell\v1.0\PowerShell.exe",
        "C:\Windows\System32\inetsrv\InetMgr.exe",
        "C:\Windows\system32\compmgmt.msc",
        "C:\Windows\system32\services.msc",
        "C:\Windows\system32\taskschd.msc"
    )

    foreach ($p in $pins) {
        try {
            if (Test-Path $p) {
                Pin-ToTaskbar $p
                Write-Log "Pinned: $p"
            } else {
                Write-Log "Skip (missing): $p"
            }
        } catch {
            Write-Log "WARNING: Failed to pin $p : $_"
        }
    }

    # Optional: any HKCU tweaks go here (Explorer options, file extensions, etc.)
    # Keep it small + idempotent.

    New-Item -ItemType File -Path $MarkerFile -Force | Out-Null
    Write-Log "user_setup completed."

    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log $_.ScriptStackTrace
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
