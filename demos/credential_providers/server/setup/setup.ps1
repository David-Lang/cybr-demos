Start-Transcript -Path "C:\PSScriptLog.txt" -Append
Get-Date -UFormat "%A /%Y%m/%d %R %Z"
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

$ScriptRoot      = Split-Path -Parent $MyInvocation.MyCommand.Path
$CYBR_DEMOS_PATH = "C:\cybr-demos"

. "$CYBR_DEMOS_PATH\demos\utility\powershell5\dotenv_functions.ps1"
. "$CYBR_DEMOS_PATH\demos\utility\powershell5\aws_functions.ps1"
. "$CYBR_DEMOS_PATH\demos\utility\powershell5\identity_functions.ps1"
. "$CYBR_DEMOS_PATH\demos\utility\powershell5\vault_functions.ps1"
. "$CYBR_DEMOS_PATH\demos\tenant_vars.ps1"

Load-DotEnv "$ScriptRoot\vars.env"

$s3_uri_cpp_installer = $S3_URI_CPP_INSTALLER
$zip_file  = $ZIP_FILE
if (-not $s3_uri_cpp_installer) { throw "S3_URI_CP_INSTALLER is empty after Load-DotEnv" }
if (-not $zip_file) { throw "ZIP_FILE is empty after Load-DotEnv" }

$installerDir = Join-Path $ScriptRoot "installer"
mkdir $installerDir -Force | Out-Null

# ---- IIS prereqs FIRST ----
$features = @(
    "Web-Server",
    "Web-Mgmt-Compat",
    "Web-Metabase",
    "Web-WMI",
    "Web-Lgcy-Scripting",
    "Web-Net-Ext45",
    "Web-Asp",
    "Web-Asp-Net45",
    "Web-ISAPI-Ext",
    "Web-ISAPI-Filter"
)

$missing = $features | Where-Object { -not (Get-WindowsFeature $_).Installed }
if ($missing) {
    Install-WindowsFeature $missing -IncludeManagementTools -Confirm:$false | Out-Null
}

Import-Module WebAdministration

Write-Host "Checking Web-Metabase Installed: $((Get-WindowsFeature Web-Metabase).Installed)"

# ---- Get file from S3 ----
$region = $env:AWS_REGION
if (-not $region) { $region = "us-east-1" }
Set-DefaultAWSRegion -Region $region

Get-S3File $s3_uri_cpp_installer

Expand-Archive -Path $zip_file -DestinationPath $installerDir -Force
Set-Location $installerDir

## ---- Prepare CCP folders ----
#$basePath = "C:\Central Credential Provider"
#$folders = @()
#$folders += $basePath
#$folders += Join-Path $basePath "Windows"
#$folders += Join-Path $basePath "Central Credential Provider Web Service"
#
#foreach ($folder in $folders) {
#    if (-not (Test-Path $folder)) {
#        New-Item -ItemType Directory -Path $folder -Force | Out-Null
#        Write-Host "Created: $folder"
#    } else {
#        Write-Host "Exists:  $folder"
#    }
#}
#Write-Host "Installing AIMWebService.msi, log location AIMWebService_install.log"

msiexec.exe /i "$installerDir\Central Credential Provider Web Service\AIMWebService.msi" /qn /l*v $installerDir\AIMWebService_install.log
if ($LASTEXITCODE -ne 0) { throw "AIMWebService MSI failed. See $installerDir\AIMWebService_install.log" }
Start-Sleep -Seconds 10

$siteName = "Default Web Site"
$appName  = "AIMWebService"

# Disable the redirects
Set-WebConfiguration system.webServer/httpRedirect "IIS:\sites\$siteName" -Value @{enabled="false"}
Set-WebConfiguration system.webServer/httpRedirect "IIS:\sites\$siteName\$appName" -Value @{enabled="false"}

# If this SSL is set then the WDSL doc page will not be avalible ({fqdn}/AIMWebService/V1.1/AIM.asmx)
# IIS Setting: AIMWebService: SSL Client Certificates: Accept
$cfgSection = Get-IISConfigSection -Location "$siteName/$appName" -SectionPath "system.webServer/security/access"
Set-IISConfigAttributeValue -ConfigElement $cfgSection -AttributeName "sslFlags" -AttributeValue "Ssl, SslNegotiateCert"

# ----- CREATE APP -----
#$token = Get-IdentityToken -IspId "$env:TENANT_ID" -ClientId "$env:CLIENT_ID" -ClientSecret "$env:CLIENT_SECRET"
#New-App -IspSubdomain "$env:TENANT_SUBDOMAIN" -IdentityToken $token -AppId "AIMWebService"


# Other things that need to be done
# Manualy create users and grant safe
# create app user on PVWA: 	AIMWebService
# create app user on PVWA: 	ccp_app1
# grant safe access to: CP Agent Prov User
# grant safe access to: App User

Get-Date -UFormat "%A /%Y%m/%d %R %Z"
Stop-Transcript

# Suppress random outputs from script or scope
$null

