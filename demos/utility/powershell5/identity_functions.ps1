function Get-IdentityToken {
    param (
        [Parameter(Mandatory = $true)]
        [string]$IspId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$ClientSecret
    )

    $uri = "https://$IspId.id.cyberark.cloud/oauth2/platformtoken"

    $headers = @{
        "X-IDAP-NATIVE-CLIENT" = "true"
        "Content-Type"        = "application/x-www-form-urlencoded"
    }

    $body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
    }

    try {
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $uri `
            -Headers $headers `
            -Body $body
    }
    catch {
        Write-Error "ERROR: Get Identity Token request failed: $($_.Exception.Message)"
        exit 1
    }

    if (-not $response.access_token) {
        Write-Error "ERROR: Get Identity Token failed. Access token is empty or null."
        exit 1
    }

    # Return token (stdout equivalent)
    return $response.access_token
}

function Get-UserByName {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$IspId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$IdentityToken,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Username
    )

    $uri = "https://$IspId.id.cyberark.cloud/CDirectoryService/GetUserByName"

    $headers = @{
        Authorization = "Bearer $IdentityToken"
        Accept        = "application/json"
    }

    $json = @{ username = $Username } | ConvertTo-Json -Compress

    try {
        $resp = Invoke-RestMethod `
            -Method Post `
            -Uri $uri `
            -Headers $headers `
            -ContentType "application/json" `
            -Body $json `
            -ErrorAction Stop
    }
    catch {
        throw "GetUserByName failed: $($_.Exception.Message)"
    }

    if (-not $resp.success) {
        throw "GetUserByName returned success=false. Message=$($resp.Message) ErrorCode=$($resp.ErrorCode) ErrorID=$($resp.ErrorID)"
    }

    $uuid = $resp.Result.Uuid
    if ([string]::IsNullOrWhiteSpace($uuid)) {
        throw "GetUserByName succeeded but Result.Uuid is empty/missing"
    }

    return $uuid
}


function Reset-UserPassword {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$IspId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$IdentityToken,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UserUuid,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UserSecret
    )

    $uri = "https://$IspId.id.cyberark.cloud/UserMgmt/ResetUserPassword"

    $headers = @{
        Authorization = "Bearer $IdentityToken"
        Accept        = "application/json"
    }

    $json = @{ ID = $UserUuid; newPassword = $UserSecret } | ConvertTo-Json -Compress

    #Write-Host "POST $uri"
    #Write-Host $json
    try {
        Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType "application/json" -Body $json -ErrorAction Stop
    }
    catch {
        throw "ResetUserPassword failed: $($_.Exception.Message)"
    }
}
