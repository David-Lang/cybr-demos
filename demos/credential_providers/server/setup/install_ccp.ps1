Start-Transcript -Append C:\PSScriptLog.txt
Get-Date -UFormat "%A /%Y%m/%d %R %Z"
Set-ExecutionPolicy Bypass -Scope process

# Get File from S3
$zip_file = "s3uri"

Expand-Archive "C:/Cyberark/CCP/$zip_file"

msiexec.exe  /i "C:\Cyberark\ccp\repack_ccp_rls_v12.6.1\repack_ccp_rls_v12.6.1\AIMWebService.msi" /qn

start-sleep -s 10

import-module webAdministration

# Manualy create users and grant safe untill cybrcli cmds added
# cybr logon -i -a cyberark -b "$pas_base_url" -u "$pas_username" -p "$pas_password" --non-interactive

# create app user on PVWA: 	AIMWebService

# create app user on PVWA: 	ccp_app1
# grant safe access to: CP Prov User
# grant safe access to: App User

$siteName = "Default Web Site"
$appName = "AIMWebService"

# Disable the redirects
Set-WebConfiguration system.webServer/httpRedirect "IIS:\sites\$siteName" -Value @{enabled="false"}
Set-WebConfiguration system.webServer/httpRedirect "IIS:\sites\$siteName\$appName" -Value @{enabled="false"}


# If this SSL is set then the WDSL doc page will not be avalible ({fqdn}/AIMWebService/V1.1/AIM.asmx)
# IIS Setting: AIMWebService: SSL Client Certificates: Accept
$cfgSection = Get-IISConfigSection -Location "$siteName/$appName" -SectionPath "system.webServer/security/access";
Set-IISConfigAttributeValue -ConfigElement $cfgSection -AttributeName "sslFlags" -AttributeValue "Ssl, SslNegotiateCert";

# Configure a hardened server to accept OS user authentication
# When hardening a server, all non-administrator users become blocked from authenticating to the hardened server using OS user authentication.
# When Central Credential Provider is installed on a hardened PVWA, you need to reconfigure the authenticated users on this server:
# Go to the Local security policy.
# Under User Rights Assignment, select Access this computer from the network.
# In the policy's properties, add the Authenticated Users group. This allows all non-administrator users to connect to Central Credential Provider using OS user authentication and successfully retrieve secrets.

Get-Date -UFormat "%A /%Y%m/%d %R %Z"
Stop-Transcript