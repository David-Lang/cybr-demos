# Demo: CP (Credential Provider)

### About: 

 - CP agent installed on the Application server
 - CP agent provides a command line app to securely retrieve credentials from the Vault
 - CP agent maintains a secure cache that contains secrets required by requesting applications (25 min default) 


### CP supports multiple Access controls:
| Access controls  | Description                                                                                                                                                                                  |
|------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Allowed Machines | Based on: IP / DNS / Hostname / IP subnet in CIDR IPv4 format                                                                                                                                |
| OS User          | The OS users under which the application runs                                                                                                                                                |
| File Path        | List of valid paths for the application. Compares the full path of the application or script file with the path specified                                                                    |
| Hash             | list of valid hash values of the application. Compares the calling application hash value with the hash values specified. The main benefit is to protect it from any malicious code changes. |

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
    participant CP
    participant Vault
    App->>CP: Command line Call 
    Note right of CP: CP Authenticates Request 
    Note right of CP: Vault Protocol: 1858
    CP->>Vault: Request Account
    Vault-->>CP: Return Account
    Note right of CP: CP Caches Account
    CP-->>App: Return Account
````

### Example:

```shell
/opt/CARKaim/sdk/clipasswordsdk GetPassword \
-p AppDescs.AppID=jumpbox_cp_app \
-p QueryFormat=2 \
-p Query="Safe=safe1;UserName=account-01" \
-p Reason="CP from jumpbox demo" \
-o Password
```
```shell
superSecret1
```

***
### Other Links:
* [About Caching](https://docs.cyberark.com/Product-Doc/OnlineHelp/AAM-CP/latest/en/Content/CP%20and%20ASCP/configuring-caching.htm#Howdoesitwork) 
* [TLS-SRP (Port 1858)](https://en.wikipedia.org/wiki/TLS-SRP)
* [IANA Service Name and Transport Protocol Port Number Registry](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml?search=1&sk=&page=23)
