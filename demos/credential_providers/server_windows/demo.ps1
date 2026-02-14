### powershell 5: example syntax ###

# Bypass https cert validation if using self signed certs
function Enable-TrustAllCertsPolicyForWindowsPowerShell {
    if ("TrustAllCertsPolicy" -as [type]) { return }  # don't Add-Type twice

    Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
  public bool CheckValidationResult(
    ServicePoint srvPoint,
    X509Certificate certificate,
    WebRequest request,
    int certificateProblem) { return true; }
}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}

Enable-TrustAllCertsPolicyForWindowsPowerShell

$pas_base_url = "https://localhost/"

# GET request with client network authentication
$apiUrl = "$pas_base_url/AIMWebService/api/Accounts"
$apiParameters = "?AppID=ccp_app1&Safe=safe1&UserName=account-01"
echo Invoke-RestMethod "$apiUrl$apiParameters" -Method Get | ConvertTo-Json -Depth 10
Invoke-RestMethod "$apiUrl$apiParameters" -Method Get | ConvertTo-Json -Depth 10

# GET request with client certificate authentication
#$apiParameters = "?AppID=ccp_app2&Safe=safe1&UserName=account-01"
#$cert = Get-PfxCertificate -FilePath "C:\cyberark\demos\app.pfx"
#Invoke-RestMethod "$apiUrl$apiParameters" -Method Get -Certificate $cert | ConvertTo-Json -Depth 10

