# Demo: CCP (Central Credential Provider)

### About: 

 - Installed on a Windows server, CCP allows applications to call an API to securely retrieve their credentials from the Vault during run-time. 
 - CCP maintains a secure cache that contains secrets required by requesting applications.
 - CCP support multiple Access controls: 


| Access controls           | Description                                                                                                                                                                    |
|---------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Allowed Machines          | Based on: IP / DNS / Hostname / IP subnet in CIDR IPv4 format                                                                                                                  |
| OS User                   | The OS users under which the application runs                                                                                                                                  |
| Certificate Serial Number | Uses the serial number of the certificate to authenticate the application                                                                                                      |
| Certificate Attribute     | Uses the SubjectAlternativeName, Subject, or Issuer attribute to authenticate the application. Certificate Attribute authentication is configurable through the REST API only. |

### Configuration:
From the PVWA
- Define an Application (AppId)
- Configure Access Controls 
- Add the Application to the required Safes 

### Workflow:

```mermaid
sequenceDiagram
    autonumber
    participant App
    participant CCP
    Note right of CCP: CCP hosted on IIS
    participant CP
    participant Vault
    App->>CCP: Api Call 
    CCP->>CP: Request Account
    Note right of CP: CP Authenticates Request
    Note right of CP: Vault Protocol: 1858
    CP->>Vault: Request Account
    Vault-->>CP: Return Account
    Note left of CP: CP Caches Account
    CP-->>CCP:  Return Account
    CCP-->>App: Return Account
````

### Example:

```shell
pas_base_url="$PAS_BASE_URL"
app_id="ccp-app1"
safe="safe1"
user_name="account-01"
curl -sk "$pas_base_url/AIMWebService/api/Accounts?AppID=$app_id&Safe=$safe&UserName=$user_name" | jq .
```
```json
{
  "Content": "superSecret1",
  "CreationMethod": "PVWA",
  "Address": "10.10.10.101",
  "Safe": "safe1",
  "UserName": "account-01",
  "Name": "Operating System-UnixSSH-10.10.10.101-account-01",
  "PolicyID": "UnixSSH",
  "DeviceType": "Operating System",
  "CPMDisabled": "No Reason",
  "Folder": "Root",
  "PasswordChangeInProcess": "False"
}
```

