# Implement CCP Certificate Attribute Authentication for Credential Retrieval

## Purpose

This guide describes how to configure CyberArk Central Credential Provider (CCP) so an application can authenticate with a client certificate and retrieve a credential, using certificate attributes such as Issuer, Subject, and Subject Alternative Name instead of binding authorization to a certificate serial number or certificate hash.

This is the preferred pattern for short-lived certificate environments because the application authorization can remain stable across certificate renewals when the issuing CA and workload identity attributes remain stable.

## Key Point

CyberArk supports two client certificate authentication patterns for CCP:

- Certificate Serial Number
- Certificate Attribute

For the use case described here, use `certificateattr`.

CyberArk documentation states that Certificate Attribute authentication can use `SubjectAlternativeName`, `Subject`, or `Issuer`, and that it is configurable through the REST API only. This explains why the option may not appear in the UI even though it can be configured.

## Target Pattern

Application request flow:

1. Application presents a client certificate to the CCP IIS endpoint.
2. IIS validates the client certificate and certificate chain.
3. CCP maps the request to the configured CyberArk application ID.
4. CyberArk validates the certificate attributes configured on that application.
5. CCP authorizes the application against the Safe permissions.
6. Application retrieves the credential from CCP.

Recommended authorization pattern:

```text
Issuer + SubjectAlternativeName
```

Acceptable fallback:

```text
Issuer + Subject
```

Avoid using only certificate serial number for this use case, because a renewed certificate changes serial number and forces CyberArk application authentication updates every renewal cycle.

## Prerequisites

- CyberArk CCP is installed and reachable over HTTPS.
- CCP web service is available at:

```text
https://<ccp-host>/AIMWebService/api/Accounts
```

- The CCP IIS endpoint is configured for SSL.
- Client certificate authentication is enabled in IIS for the CCP endpoint.
- The CA that signs the client certificate is trusted by the CCP server.
- CRL or OCSP access is available if certificate revocation checking is enforced.
- A credential already exists in a CyberArk Safe.
- The application has or will have an AppID in CyberArk.
- The application has permission to retrieve the target account from the Safe.
- You have a CyberArk user/API token with permission to manage applications.

## Step 1: Inspect the Client Certificate

Use OpenSSL or a certificate management tool to capture the certificate attributes that should authorize the workload.

```bash
openssl x509 -in client.crt -noout -issuer -subject
openssl x509 -in client.crt -noout -text | sed -n '/Subject Alternative Name/,+1p'
```

Example output:

```text
issuer=CN=Enterprise Issuing CA,OU=PKI,O=Example Corp,C=US
subject=CN=orders-api.prod.example.com,OU=Payments,O=Example Corp,C=US
X509v3 Subject Alternative Name:
    DNS:orders-api.prod.example.com, URI:spiffe://example.com/prod/orders-api
```

Choose attributes that are stable across certificate renewal.

Recommended:

- Issuer CA identity
- SAN DNS name or SAN URI representing the workload identity

Use Subject only if the subject is stable and governed by certificate policy.

## Step 2: Create the CyberArk Application

If the application does not already exist, create it through the CyberArk REST API.

Endpoint:

```text
POST https://<pvwa-host>/PasswordVault/WebServices/PIMServices.svc/Applications/
```

Example body:

```json
{
  "application": {
    "AppID": "orders-api-prod",
    "Description": "Orders API credential retrieval",
    "Location": "\\Applications",
    "Disabled": false,
    "BusinessOwnerFName": "App",
    "BusinessOwnerLName": "Owner",
    "BusinessOwnerEmail": "app.owner@example.com"
  }
}
```

The API call requires an authenticated CyberArk session token in the `Authorization` header.

## Step 3: Add Certificate Attribute Authentication

Add the certificate attribute authentication method to the application.

Endpoint:

```text
POST https://<pvwa-host>/PasswordVault/WebServices/PIMServices.svc/Applications/{AppID}/Authentications/
```

Example using Issuer and SAN:

```json
{
  "authentication": {
    "AuthType": "certificateattr",
    "Issuer": [
      "CN=Enterprise Issuing CA",
      "OU=PKI",
      "O=Example Corp",
      "C=US"
    ],
    "SubjectAlternativeName": [
      "DNS Name=orders-api.prod.example.com",
      "URI=spiffe://example.com/prod/orders-api"
    ],
    "Comment": "Authorize renewed client certificates for orders-api-prod by issuer and SAN"
  }
}
```

Example using Issuer and Subject:

```json
{
  "authentication": {
    "AuthType": "certificateattr",
    "Issuer": [
      "CN=Enterprise Issuing CA",
      "OU=PKI",
      "O=Example Corp",
      "C=US"
    ],
    "Subject": [
      "CN=orders-api.prod.example.com",
      "OU=Payments",
      "O=Example Corp",
      "C=US"
    ],
    "Comment": "Authorize renewed client certificates for orders-api-prod by issuer and subject"
  }
}
```

CyberArk-supported SAN attribute names include:

- `DNS Name`
- `IP Address`
- `URI`
- `RFC822 Name`

Use exact values from the certificate. Attribute matching is sensitive to formatting, so validate against the target CCP/PVWA version before bulk rollout.

## Step 4: Add Allowed Machines as a Second Control

Certificate attributes identify the workload certificate. Add Allowed Machines where possible to restrict where that AppID can be used.

Endpoint:

```text
POST https://<pvwa-host>/PasswordVault/WebServices/PIMServices.svc/Applications/{AppID}/Authentications/
```

Example:

```json
{
  "authentication": {
    "AuthType": "machineAddress",
    "AuthValue": "10.20.30.0/24"
  }
}
```

For cloud environments, prefer a stable CIDR, hostname, or DNS value rather than a single ephemeral IP address.

## Step 5: Grant Safe Access

Add the application as an authorized Safe member with the minimum permissions required to retrieve the credential.

At minimum, the application needs permission to retrieve the target credential. Keep the Safe scoped to the application or application group where possible.

Recommended Safe pattern:

```text
Safe per application or application domain
```

Example:

```text
Safe: APP-ORDERS-PROD
Account object: orders-prod-credential
AppID: orders-api-prod
```

## Step 6: Retrieve the Credential

Use the CCP REST endpoint with the client certificate.

Example:

```bash
curl \
  --cert client.crt \
  --key client.key \
  "https://<ccp-host>/AIMWebService/api/Accounts?AppID=orders-api-prod&Safe=APP-ORDERS-PROD&Object=orders-prod-credential"
```

If the private key is bundled in a PFX/P12 file, convert to PEM or use a client/runtime that supports PFX directly.

Example conversion:

```bash
openssl pkcs12 -in client.p12 -clcerts -nokeys -out client.crt
openssl pkcs12 -in client.p12 -nocerts -nodes -out client.key
```

Expected result:

```json
{
  "Content": "<credential-value>",
  "UserName": "<credential-username>",
  "Address": "<target-address>"
}
```

Response fields vary by account type and CCP configuration.

## Step 7: Validate Certificate Renewal Behavior

To prove the short-lived certificate use case:

1. Issue certificate version 1 with the approved Issuer and SAN or Subject.
2. Retrieve the credential successfully.
3. Issue certificate version 2 with a new serial number but the same approved Issuer and SAN or Subject.
4. Retrieve the credential again without changing the CyberArk application authentication entry.

Expected result:

```text
Certificate renewal succeeds without updating CyberArk authentication metadata.
```

If renewal fails, compare the exact Issuer, Subject, and SAN values between the two certificates.

## Troubleshooting

### 403 or client certificate not received

Check IIS SSL settings for the CCP virtual directory:

- SSL is required.
- Client certificates are set to `Accept` or `Require`.
- The client certificate chain is trusted by the CCP server.
- Revocation checks can reach CRL or OCSP endpoints.

### CyberArk authentication failure

Check:

- AppID is correct.
- Certificate attributes exactly match the configured values.
- SAN type is formatted as `DNS Name`, `IP Address`, `URI`, or `RFC822 Name`.
- The application has Safe permissions.
- Allowed Machines does not exclude the calling host.
- Load balancer preserves source IP or sends the expected `X-Forwarded-For` value if Allowed Machines is used.

### Works with serial number but not attributes

Confirm that the application authentication method was added through the REST API as `certificateattr`. The UI may show certificate serial number support but not expose certificate attribute configuration.

### Works before certificate renewal but fails after renewal

Inspect the renewed certificate:

```bash
openssl x509 -in renewed-client.crt -noout -serial -issuer -subject
openssl x509 -in renewed-client.crt -noout -text | sed -n '/Subject Alternative Name/,+1p'
```

The serial number should change. The Issuer and selected Subject or SAN values must remain stable.

## Operational Guidance

For 47-day or other short-lived certificates, do not authorize CCP access by serial number unless there is automation to update CyberArk on every renewal. The better operating model is to authorize by stable workload identity attributes:

- Issuing CA
- DNS SAN
- URI SAN
- Governed Subject values

Recommended policy:

```text
Issuer AND workload SAN
```

Avoid broad policies such as issuer-only unless the CA is dedicated to a narrow workload population.

## UI Gap / PM Note

The UI gap is real from an implementation perspective: certificate serial number is visible in the UI workflow, while certificate attribute authentication is API-only. For customers adopting short-lived certificates, this creates an operational problem because the visible UI option encourages binding authorization to a certificate instance rather than to the workload identity.

Recommended product requirement:

```text
Expose Certificate Attribute authentication in the CCP application UI, including Issuer, Subject, and Subject Alternative Name fields.
```

Recommended UI behavior:

- Allow Issuer + Subject matching.
- Allow Issuer + SAN matching.
- Support SAN types: DNS Name, IP Address, URI, RFC822 Name.
- Show guidance that serial number is not recommended for short-lived certificate renewal workflows.
- Provide test/validate behavior against an uploaded or pasted certificate.

## Sources

- CyberArk Docs, Add applications: https://docs.cyberark.com/credential-providers/latest/en/content/common/adding-applications.htm
- CyberArk Docs, Application authentication methods: https://docs.cyberark.com/credential-providers/latest/en/content/cp%20and%20ascp/application-authentication-methods-general.htm
- CyberArk Docs, Add application authentication method: https://docs.cyberark.com/pam-self-hosted/latest/en/content/webservices/add%20authentication.htm
- CyberArk Docs, Central Credential Provider web service configuration: https://docs.cyberark.com/credential-providers/latest/en/content/ccp/configure_ccpwindows.htm
