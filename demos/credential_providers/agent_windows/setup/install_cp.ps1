Start-Transcript -Append C:\PSScriptLog.txt
Get-Date -UFormat "%A /%Y%m/%d %R %Z"
Set-ExecutionPolicy Bypass -Scope process

# Load utility functions
. (Resolve-Path "$PSScriptRoot\..\..\utility\powershell5\dotenv_functions.ps1")
. (Resolve-Path "$PSScriptRoot\..\..\utility\powershell5\aws_functions.ps1")
Load-DotEnv "..\..\..\setup_vars.env"

# Local setup
Load-DotEnv "vars.env"
$s3_uri = $S3_URI
$zip_file = $ZIP_FILE
$s3_akey = $S3_AKEY
$s3_skey = $S3_SKEY
$vault_fqdn = "vault-$TENANT_SUBDOMAIN.privilegecloud.cyberark.cloud"

# Get File from S3
Connect-AWS -AccessKey $s3_akey -SecretKey $s3_skey
Get-S3File $s3_uri

Expand-Archive "$zip_file"

# Steps to Create the silent.ini file
# do not use cred file, advanced setup, vault IP, cred user name
#.\setup.exe /r /f1"C:/Cyberark/CP/Installer/silent.iss"

#$content = [System.IO.File]::ReadAllText("$silent_path").Replace("{{vault_fqdn}}",$vault_ip)
#[System.IO.File]::WriteAllText("$silent_path", $content)
#
#start-sleep -s 2
## first run partialy succededs?
#.\setup.exe /s /f1"C:/Cyberark/CP/Installer/silent.iss"
#start-sleep -s 2
#
## run a second time?, now files should be in the installation directory: C:\Program Files\CyberArk\ApplicationPasswordProvider
#.\setup.exe /s /f1"C:/Cyberark/CP/Installer/silent.iss"
#start-sleep -s 2
#
## edit vault ini file
#$vault_path = "C:\Program Files\CyberArk\ApplicationPasswordProvider\Vault\Vault.ini"
##rm $vault_path
#$content = [System.IO.File]::ReadAllText("$vault_path").Replace("{{vault_fqdn}}",$vault_ip)
#[System.IO.File]::WriteAllText("$vault_path", $content)
#
#
## Run script after reboot
#$scriptPath = "C:\Cyberark\cp\after_reboot.ps1"
#$taskName = "after_reboot_cp_install"
#$taskpath = "\cybr-demos"
#$argument = "-WindowStyle Hidden -Command `"& '$scriptPath'`""
#$action = (New-ScheduledTaskAction -Execute "${Env:WinDir}\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $argument)
#$trigger = (New-ScheduledTaskTrigger -AtStartup)
#$principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
#
#Register-ScheduledTask -TaskName "$taskName" -TaskPath $taskPath -Action $action -Trigger $trigger -Principal $principal ;

Get-Date -UFormat "%A /%Y%m/%d %R %Z"
Stop-Transcript
