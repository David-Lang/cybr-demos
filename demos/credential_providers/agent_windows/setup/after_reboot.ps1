Start-Transcript -Append C:\PSScriptLog.txt
Get-Date -UFormat "%A /%Y%m/%d %R %Z"
Set-ExecutionPolicy Bypass -Scope process

$lab_pwd = [IO.File]::ReadAllText("C:/Cyberark/cybrlab/lab_pwd_out.txt").Trim()

cd "C:\Program Files\CyberArk\ApplicationPasswordProvider\Env"
# #CreateEnv parameteres for readability
# CreateEnv.exe
# /Username administrator
# /Password CyberArk11@@
# /InstallationFolder "C:\Program Files\CyberArk\ApplicationPasswordProvider"
# /AppProviderUser prov_pas_comp_ccp
# /AppProviderConfSafe  AppProviderConf
# /MainAppProviderConfFilePath "C:\Program Files\CyberArk\ApplicationPasswordProvider\Env\main_appprovider.conf.Win.12.06"
# /OverrideExistingConfFile Y
# /OverrideExistingCredFile Y
# /AppProviderUserLocation Applications
./CreateEnv.exe /Username administrator /Password $lab_pwd /InstallationFolder "C:\Program Files\CyberArk\ApplicationPasswordProvider" /AppProviderUser prov_pas_comp_ccp /AppProviderConfSafe  AppProviderConf /MainAppProviderConfFilePath "C:\Program Files\CyberArk\ApplicationPasswordProvider\Env\main_appprovider.conf.Win.12.06" /OverrideExistingConfFile Y /OverrideExistingCredFile Y /AppProviderUserLocation Applications

Disable-ScheduledTask -TaskName "after_reboot_cp_install" -TaskPath "\cybrlab"

# change conf (in Safe with private-ark, or make sure to set value on install):
# Optional: change cache time to 15 seconds

# restart windows service
net stop "CyberArk Application Password Provider"
net start "CyberArk Application Password Provider"

Get-Date -UFormat "%A /%Y%m/%d %R %Z"
Stop-Transcript
