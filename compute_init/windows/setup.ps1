# compute_init\windows\setup.ps1
# Controller-only: minimal lines; delegates all work to the install_* scripts in this folder.
# Contract:
#   exit 0    => done
#   exit 3010 => reboot required (controller will reboot + re-run at next boot)
#   exit 1    => failure (scheduled task retry will handle)

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$BootstrapDir = "C:\bootstrap"
$LogDir       = "$BootstrapDir\logs"
New-Item -ItemType Directory -Path $BootstrapDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
New-Item -ItemType File -Path "$BootstrapDir\setup.started" -Force | Out-Null

Start-Transcript -Append "$LogDir\setup_log.txt" | Out-Null
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

function Invoke-Step {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path $Path)) { throw "Missing script: $Path" }
    Write-Host "# Running $(Split-Path -Leaf $Path)"

    # Run in a fresh PowerShell so we get a REAL process exit code
    $p = Start-Process -FilePath "powershell.exe" -Wait -PassThru -NoNewWindow `
    -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy","Bypass",
        "-File", "`"$Path`""
    )

    if ($p.ExitCode -eq 3010) { $script:NeedsReboot = $true; return }
    if ($p.ExitCode -ne 0)    { throw "$Path failed with exit code $($p.ExitCode)" }
}


function Test-PendingReboot {
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { return $true }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { return $true }
    try {
        $p = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($p.PendingFileRenameOperations) { return $true }
    } catch {}
    return $false
}

try {
    $script:NeedsReboot = $false

    # --- Keep this list tight: controller just sequences modules ---
    Invoke-Step "$ScriptRoot\install_nuget.ps1"
    Invoke-Step "$ScriptRoot\install_chocolatey.ps1"
    Invoke-Step "$ScriptRoot\install_git.ps1"
    Invoke-Step "$ScriptRoot\install_bruno.ps1"
    Invoke-Step "$ScriptRoot\install_ps7.ps1"
    Invoke-Step "$ScriptRoot\install_notepad++.ps1"
    Invoke-Step "$ScriptRoot\install_chrome.ps1"
    Invoke-Step "$ScriptRoot\install_aws_tools.ps1"
    Invoke-Step "$ScriptRoot\install_iis.ps1"

    # UI/session steps (taskbar pins, explorer tweaks, HKCU shell customization).
    # --- Register user_setup to run once at Administrator logon ---
    $UserScript = Join-Path $ScriptRoot "user_setup.ps1"
    $TaskName   = "BootstrapUserSetup"
    $Marker     = "C:\bootstrap\user_setup.completed"

    if (-not (Test-Path $Marker)) {
        # Trigger at logon (Administrator)
        $Action   = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$UserScript`""
        $Trigger  = New-ScheduledTaskTrigger -AtLogOn -User "Administrator"
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

        $Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null
    }

    New-Item -ItemType File -Path "$BootstrapDir\setup.completed" -Force | Out-Null

    if ($script:NeedsReboot -or (Test-PendingReboot)) {
        Write-Host "# Reboot required"
        Stop-Transcript | Out-Null
        exit 3010
    }

    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

