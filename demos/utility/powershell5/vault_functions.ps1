#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-CybrRest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PUT','DELETE')] [string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Token,
        [Parameter()][object]$Body = $null,
        [Parameter()][hashtable]$ExtraHeaders = @{}
    )

    $headers = @{
        Authorization = "Bearer $Token"
        Accept        = "application/json"
    }
    foreach ($k in $ExtraHeaders.Keys) { $headers[$k] = $ExtraHeaders[$k] }

    $params = @{
        Method      = $Method
        Uri         = $Uri
        Headers     = $headers
        ErrorAction = "Stop"
    }

    if ($null -ne $Body) {
        $params["ContentType"] = "application/json"
        if ($Body -is [string]) {
            $params["Body"] = $Body
        } else {
            $params["Body"] = ($Body | ConvertTo-Json -Depth 20)
        }
    }

    Invoke-RestMethod @params
}

function New-Safe {
    param(
        [Parameter(Mandatory)][string]$IspSubdomain,
        [Parameter(Mandatory)][string]$IdentityToken,
        [Parameter(Mandatory)][string]$SafeName
    )

    Write-Host "`nCreating Safe: $SafeName"

    $uri = "https://$IspSubdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Safes"
    $body = @{
        numberOfDaysRetention     = 0
        numberOfVersionsRetention = $null
        oLACEnabled               = $true
        autoPurgeEnabled          = $true
        managingCPM               = ""
        safeName                  = $SafeName
        description               = "poc safe"
        location                  = ""
    }

    Invoke-CybrRest -Method POST -Uri $uri -Token $IdentityToken -Body $body
}

function Remove-Safe {
    param(
        [Parameter(Mandatory)][string]$IspSubdomain,
        [Parameter(Mandatory)][string]$IdentityToken,
        [Parameter(Mandatory)][string]$SafeName
    )

    Write-Host "`nDeleting Safe: $SafeName"

    # If SafeName can contain spaces/special chars, URL-encode it
    $safeUrlId = [System.Uri]::EscapeDataString($SafeName)

    $uri = "https://$IspSubdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Safes/$safeUrlId"
    Invoke-CybrRest -Method DELETE -Uri $uri -Token $IdentityToken
}

function Add-SafeAdminRole {
    param(
        [Parameter(Mandatory)][string]$IspSubdomain,
        [Parameter(Mandatory)][string]$IdentityToken,
        [Parameter(Mandatory)][string]$SafeName,
        [Parameter(Mandatory)][string]$MemberName
    )

    Write-Host "`nAdding Member: `"$MemberName`" to Safe: `"$SafeName`""

    $safeEsc = [System.Uri]::EscapeDataString($SafeName)
    $uri = "https://$IspSubdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Safes/$safeEsc/Members/"

    $body = @{
        memberName                = $MemberName
        searchIn                  = "Vault"
        membershipExpirationDate  = $null
        isReadOnly                = $true
        permissions               = @{
            useAccounts                              = $true
            retrieveAccounts                         = $true
            listAccounts                             = $true
            addAccounts                              = $true
            updateAccountContent                     = $true
            updateAccountProperties                  = $true
            initiateCPMAccountManagementOperations   = $true
            specifyNextAccountContent                = $true
            renameAccounts                           = $true
            deleteAccounts                           = $true
            unlockAccounts                           = $true
            manageSafe                               = $true
            manageSafeMembers                        = $true
            backupSafe                               = $true
            viewAuditLog                             = $true
            viewSafeMembers                          = $true
            accessWithoutConfirmation                = $true
            createFolders                            = $true
            deleteFolders                            = $true
            moveAccountsAndFolders                   = $true
            requestsAuthorizationLevel1              = $false
            requestsAuthorizationLevel2              = $false
        }
        MemberType               = "Role"
    }

    Invoke-CybrRest -Method POST -Uri $uri -Token $IdentityToken -Body $body
}

function Add-SafeReadMember {
    param(
        [Parameter(Mandatory)][string]$IspSubdomain,
        [Parameter(Mandatory)][string]$IdentityToken,
        [Parameter(Mandatory)][string]$SafeName,
        [Parameter(Mandatory)][string]$MemberName
    )

    Write-Host "`nAdding Member: $MemberName to Safe: $SafeName"

    $safeEsc = [System.Uri]::EscapeDataString($SafeName)
    $uri = "https://$IspSubdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Safes/$safeEsc/Members/"

    $body = @{
        memberName               = $MemberName
        searchIn                 = "Vault"
        membershipExpirationDate = $null
        isReadOnly               = $true
        permissions              = @{
            useAccounts                            = $false
            retrieveAccounts                       = $true
            listAccounts                           = $true
            addAccounts                            = $false
            updateAccountContent                   = $false
            updateAccountProperties                = $false
            initiateCPMAccountManagementOperations = $false
            specifyNextAccountContent              = $false
            renameAccounts                         = $false
            deleteAccounts                         = $false
            unlockAccounts                         = $false
            manageSafe                             = $false
            manageSafeMembers                      = $false
            backupSafe                             = $false
            viewAuditLog                           = $false
            viewSafeMembers                        = $true
            accessWithoutConfirmation              = $true
            createFolders                          = $false
            deleteFolders                          = $false
            moveAccountsAndFolders                 = $false
            requestsAuthorizationLevel1            = $false
            requestsAuthorizationLevel2            = $false
        }
        MemberType               = "User"
    }

    Invoke-CybrRest -Method POST -Uri $uri -Token $IdentityToken -Body $body
}

function New-AccountSshUser1 {
    param(
        [Parameter(Mandatory)][string]$IspSubdomain,
        [Parameter(Mandatory)][string]$IdentityToken,
        [Parameter(Mandatory)][string]$SafeName
    )

    Write-Host "`nCreating Account: account-ssh-user-1 in Safe: $SafeName"

    $uri = "https://$IspSubdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts/"

    $body = @{
        name                     = "account-ssh-user-1"
        address                  = "196.168.0.1"
        userName                 = "ssh-user-1"
        platformId               = "UnixSSH"
        safeName                 = $SafeName
        secretType               = "key"
        secret                   = "SuperSecret1!"
        platformAccountProperties = @{}
        secretManagement         = @{
            automaticManagementEnabled = $true
            manualManagementReason     = ""
        }
        remoteMachinesAccess     = @{
            remoteMachines                 = ""
            accessRestrictedToRemoteMachines = $true
        }
    }

    Invoke-CybrRest -Method POST -Uri $uri -Token $IdentityToken -Body $body
}

function Remove-AccountSshUser1 {
    param(
        [Parameter(Mandatory)][string]$IspSubdomain,
        [Parameter(Mandatory)][string]$IdentityToken,
        [Parameter(Mandatory)][string]$SafeName
    )

    Write-Host "`nDeleting Account: account-ssh-user-1 in Safe: $SafeName"

    # Note: your bash used: filter=safename%20eq%20$3  (not quoted)
    # This version URL-encodes the filter properly and quotes the safe name.
    $filter = [System.Uri]::EscapeDataString("safename eq $SafeName")
    $uriList = "https://$IspSubdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts?filter=$filter"

    $resp = Invoke-CybrRest -Method GET -Uri $uriList -Token $IdentityToken

    if (-not $resp.value -or $resp.value.Count -lt 1) {
        Write-Host "No accounts found for safe: $SafeName"
        return
    }

    $id = $resp.value[0].id
    Write-Host "`nDeleting Account Id: account-ssh-user-1 in Safe: $SafeName Id: $id"

    $uriDel = "https://$IspSubdomain.privilegecloud.cyberark.cloud/PasswordVault/API/Accounts/$id"
    Invoke-CybrRest -Method DELETE -Uri $uriDel -Token $IdentityToken
}

function New-App {
    param(
        [Parameter(Mandatory)][string]$IspSubdomain,
        [Parameter(Mandatory)][string]$IdentityToken,
        [Parameter(Mandatory)][string]$AppId
    )

    Write-Host "`nCreating Application: $AppId"

    $uri = "https://$IspSubdomain.privilegecloud.cyberark.cloud/PasswordVault/WebServices/PIMServices.svc/Applications/"
    $body = @{
        application = @{
            AppID = $AppId
        }
    }

    Invoke-CybrRest -Method POST -Uri $uri -Token $IdentityToken -Body $body
}

function Add-AppAuthentication {
    param(
        [Parameter(Mandatory)][string]$IspSubdomain,
        [Parameter(Mandatory)][string]$IdentityToken,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$AuthType,
        [Parameter(Mandatory)][string]$AuthValue
    )

    # AuthType examples:
    # machineAddress, osUser, path, hash, certificate, domain, group

    Write-Host "`nAdding $AuthType auth to Application: $AppId ($AuthValue)"

    $appEsc = [System.Uri]::EscapeDataString($AppId)
    $uri = "https://$IspSubdomain.privilegecloud.cyberark.cloud/PasswordVault/WebServices/PIMServices.svc/Applications/$appEsc/Authentications/"

    $body = @{
        authentication = @{
            AuthType  = $AuthType
            AuthValue = $AuthValue
        }
    }

    Invoke-CybrRest -Method POST -Uri $uri -Token $IdentityToken -Body $body
}

function Add-AppCertificateAttrAuthentication {
    param(
        [Parameter(Mandatory)][string]$IspSubdomain,
        [Parameter(Mandatory)][string]$IdentityToken,
        [Parameter(Mandatory)][string]$AppId,

    # Pass these as JSON arrays (strings) OR as PowerShell string arrays.
        [Parameter(Mandatory)][object]$Issuer,
        [Parameter(Mandatory)][object]$Subject,
        [Parameter(Mandatory)][object]$SubjectAlternativeName
    )

    Write-Host "`nAdding certificateattr auth to Application: $AppId"

    $issuerArr  = if ($Issuer -is [string]) { $Issuer  | ConvertFrom-Json } else { $Issuer }
    $subjectArr = if ($Subject -is [string]) { $Subject | ConvertFrom-Json } else { $Subject }
    $sanArr     = if ($SubjectAlternativeName -is [string]) { $SubjectAlternativeName | ConvertFrom-Json } else { $SubjectAlternativeName }

    $appEsc = [System.Uri]::EscapeDataString($AppId)
    $uri = "https://$IspSubdomain.privilegecloud.cyberark.cloud/PasswordVault/WebServices/PIMServices.svc/Applications/$appEsc/Authentications/"

    $body = @{
        authentication = @{
            AuthType               = "certificateattr"
            Issuer                 = $issuerArr
            Subject                = $subjectArr
            SubjectAlternativeName  = $sanArr
        }
    }

    Invoke-CybrRest -Method POST -Uri $uri -Token $IdentityToken -Body $body
}

function Update-IpAllowlist {
    param(
        [Parameter(Mandatory)][string]$IspSubdomain,
        [Parameter(Mandatory)][string]$IdentityToken,
    # Accept JSON array string '["1.0.0.4/32","2.0.0.5/24"]' OR string[].
        [Parameter(Mandatory)][object]$CustomerPublicIPs
    )

    $ips = if ($CustomerPublicIPs -is [string]) { $CustomerPublicIPs | ConvertFrom-Json } else { $CustomerPublicIPs }

    Write-Host "`nUpdating Privilege Cloud IP Allowlist: $($ips -join ', ')"

    $uri = "https://$IspSubdomain.privilegecloud.cyberark.cloud/api/advanced-settings/ip-allowlist"
    $body = @{
        customerPublicIPs = $ips
    }

    Invoke-CybrRest -Method PUT -Uri $uri -Token $IdentityToken -Body $body
}

function Add-IpToPrivilegeCloudAllowlist {
    param(
        [Parameter(Mandatory)][string]$IspSubdomain,
        [Parameter(Mandatory)][string]$IdentityToken
    )

    $ip = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com/" -Method GET -ErrorAction Stop).Trim()

    # Fetch current allowlist
    $uriGet = "https://$IspSubdomain.privilegecloud.cyberark.cloud/api/advanced-settings/ip-allowlist"
    $response = Invoke-CybrRest -Method GET -Uri $uriGet -Token $IdentityToken

    $ipCidr = "$ip/32"

    if ($response.customerPublicIPs -and ($response.customerPublicIPs -contains $ipCidr)) {
        Write-Host "Result: $ipCidr is already allowed."
        return
    }

    $current = @()
    if ($response.customerPublicIPs) { $current = @($response.customerPublicIPs) }

    $updated = $current + $ipCidr

    Write-Host "Adding: $ipCidr to the allowlist."
    Update-IpAllowlist -IspSubdomain $IspSubdomain -IdentityToken $IdentityToken -CustomerPublicIPs $updated

    Write-Host "`nWaiting 10 minutes for Privilege Cloud Allow List update to complete..."
    Start-Sleep -Seconds 600
}

<#
# Example usage:

$IspSubdomain = "your-tenant-subdomain"
$Token = "eyJ..."  # identity token bearer

New-Safe -IspSubdomain $IspSubdomain -IdentityToken $Token -SafeName "poc-safe-1"
Add-SafeAdminRole -IspSubdomain $IspSubdomain -IdentityToken $Token -SafeName "poc-safe-1" -MemberName "Vault Admins"
Add-SafeReadMember -IspSubdomain $IspSubdomain -IdentityToken $Token -SafeName "poc-safe-1" -MemberName "SomeUser"

New-AccountSshUser1 -IspSubdomain $IspSubdomain -IdentityToken $Token -SafeName "poc-safe-1"
Remove-AccountSshUser1 -IspSubdomain $IspSubdomain -IdentityToken $Token -SafeName "poc-safe-1"

New-App -IspSubdomain $IspSubdomain -IdentityToken $Token -AppId "MyApp01"
Add-AppAuthentication -IspSubdomain $IspSubdomain -IdentityToken $Token -AppId "MyApp01" -AuthType "machineAddress" -AuthValue "203.0.113.0/24"

Add-AppCertificateAttrAuthentication -IspSubdomain $IspSubdomain -IdentityToken $Token -AppId "MyApp01" `
  -Issuer '["CN=Thawte RSA CA 2018","OU=www.digicert.com"]' `
  -Subject '["CN=yourcompany.com","OU=IT","C=IL"]' `
  -SubjectAlternativeName '["DNS Name=www.example.com","IP Address=1.2.3.4"]'

Add-IpToPrivilegeCloudAllowlist -IspSubdomain $IspSubdomain -IdentityToken $Token
#>

#function Update-IpAllowlist {
#    param (
#        [Parameter(Mandatory)] [string]$Subdomain,
#        [Parameter(Mandatory)] [string]$IdentityToken,
#        [Parameter(Mandatory)] [string]$IpListJson   # e.g. ["1.0.0.4/32","2.0.0.5/24"]
#    )
#
#    Write-Host "`nUpdating Privilege Cloud IP Allowlist: $IpListJson"
#
#    $uri = "https://$Subdomain.privilegecloud.cyberark.cloud/api/advanced-settings/ip-allowlist"
#
#    $headers = @{
#        Authorization = "Bearer $IdentityToken"
#        Accept        = "application/json"
#    }
#
#    # Build body exactly like bash: { "customerPublicIPs": <json array> }
#    $bodyJson = "{ `"customerPublicIPs`": $IpListJson }"
#
#    #Write-Host "PUT $uri"
#    #Write-Host $bodyJson
#
#    Invoke-RestMethod `
#        -Method Put `
#        -Uri $uri `
#        -Headers $headers `
#        -ContentType "application/json" `
#        -Body $bodyJson `
#        -ErrorAction Stop
#}
#
#
#function Add-IpToPrivilegeCloudAllowList {
#    param (
#        [string]$Subdomain,
#        [string]$IdentityToken
#    )
#
#    # Get current public IP
#    $ip = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com").Trim()
#
#    $uri = "https://$Subdomain.privilegecloud.cyberark.cloud/api/advanced-settings/ip-allowlist"
#
#    # Fetch current allowlist
#    $response = Invoke-RestMethod `
#        -Method Get `
#        -Uri $uri `
#        -Headers @{
#        Authorization = "Bearer $IdentityToken"
#        Accept = "application/json"
#    }
#
#    # Check if IP already exists
#    if ($response.customerPublicIPs -contains $ip) {
#        Write-Host "Result: $ip is already allowed."
#        return
#    }
#
#    $ipCidr = "$ip/32"
#    Write-Host "Adding: $ipCidr to the allowlist."
#
#    # Append IP
#    $updatedIps = $response.customerPublicIPs + $ipCidr
#    $updatedIpsJson = $updatedIps | ConvertTo-Json -Compress
#
#    Update-IpAllowlist `
#        -Subdomain $Subdomain `
#        -IdentityToken $IdentityToken `
#        -IpListJson $updatedIpsJson
#
#    Write-Host "`nWaiting 10 minutes for Privilege Cloud Allow List update to complete..."
#    Start-Sleep -Seconds 600
#}
