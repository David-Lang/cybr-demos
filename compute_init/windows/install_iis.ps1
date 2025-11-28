
Install-WindowsFeature -name Web-Server -IncludeManagementTools

Install-WindowsFeature -name Web-Asp-Net45

Get-WindowsFeature Web-Server

# Restart-Computer -Force

$cert = New-SelfSignedCertificate -DnsName "www.example.com" -CertStoreLocation "cert:\LocalMachine\My"

Import-Module WebAdministration

if ($binding -eq $null) {
    New-WebBinding -Name "Default Web Site" -IP "*" -Port 443 -Protocol https
}
$binding = Get-WebBinding -Name "Default Web Site" -Protocol https

# Test defualt website
Invoke-WebRequest http://localhost


##
##
### Failed to run commnad
###$binding.AddSslCertificate($cert.Thumbprint, "my")

## Some manual work required on these commands
#$thumbprint = "<Thumbprint>" # Replace <Thumbprint> with your certificate's thumbprint
#$ipAddress = "0.0.0.0" # Use 0.0.0.0 for all IP addresses or specify one
#$port = 443 # Default SSL port
#$siteName = "Default Web Site" # Change this if you are not using the default site
#
#$certHash = $thumbprint
#$appId = [Guid]::NewGuid().ToString() # Generate a new GUID for the app ID
#
#Invoke-Expression "netsh http add sslcert ipport=$ipAddress:$port certhash=$certHash appid=`"{$appId}`" certstorename=MY"
