Start-Transcript -Append C:\PSScriptLog.txt
Get-Date -UFormat "%A /%Y%m/%d %R %Z"
Set-ExecutionPolicy Bypass -Scope process

$CYBR_DEMOS_PATH = "$HOME\cybr-demos"

# Load utility functions
#demo_path
. "$CYBR_DEMOS_PATH\demos\utility\powershell5\dotenv_functions.ps1"
. "$CYBR_DEMOS_PATH\demos\utility\powershell5\aws_functions.ps1"
Load-DotEnv "$CYBR_DEMOS_PATH\demos\setup_vars.env"

# Local setup
Load-DotEnv "vars.env"
$s3_uri = $S3_URI
$zip_file = $ZIP_FILE
$s3_akey = $S3_AKEY
$s3_skey = $S3_SKEY
$vault_fqdn = "vault-$TENANT_SUBDOMAIN.privilegecloud.cyberark.cloud"

###
### Add Agent IP to Privledge Cloud Allow List
###

# Get File from S3
Connect-AWS -AccessKey $s3_akey -SecretKey $s3_skey
Get-S3File $s3_uri

Expand-Archive -Path $zip_file -DestinationPath ./installer -Force
cd "./installer"

# Steps to Create the silent.ini file in Record mode
# !Do not use cred file, advanced setup, vault IP, cred user name
#
# Instead of manually configuring a response file before running the silent CP installation,
# Record mode runs an interactive CP installation, collects the values provided during the installation,
# and saves them to a response file.
# The response file is fully defined and can be used when installing other CPs using Full silent mode.
# This is especially useful if you are setting up a wide-scale installation of CPs.
# $record_file = "$(pwd)\record.iss"
# .\setup.exe /r /f1"$record_file"


$record_file = "record.iss"
$silent_file = "silent.iss"
cp ../$record_file $silent_file
(Get-Content $silent_file) -replace "szEdit1='\s*'", ("szEdit1='$vault_fqdn'") | Set-Content $silent_file

start-sleep -s 1
## first run partialy succededs?
.\setup.exe /s /f1"silent.iss"
start-sleep -s 2

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
