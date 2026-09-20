# Runtime Path Probes

This folder contains the standalone verification probe used to test the active SmartLife backend endpoint (`https://zxuacde.smart-zte.com`) using recovered runtime credentials.

---

## Included Files

- **`Invoke-Runtime-AppAuth-AccountProbes.ps1`**: Standalone PowerShell 7 script testing `/account/verify.serv`, `/account/person/signup.serv`, `/account/password/reset.serv`, and `/auth/login.serv` against `zxuacde.smart-zte.com`.

---

## Environment Reconciliation

During research, two different environments were observed:

1. **Earlier Test Path (`uactest.ztems.com`)**: Initial testing environment where account deletion without a user token succeeded.
2. **Current Production Path (`zxuacde.smart-zte.com`)**: Active host selected by official clients. On this host:
   - Account verification oracle reproduced (`code=0004` vs `code=0000 + accountId`).
   - Password reset without verification code reproduced (`code=0000`).
   - Post-reset login reproduced (`code=0000` with session token).
   - Arbitrary email pre-registration / squatting reproduced (`code=0000`).
   - Account deletion without token was rejected (`code=3001`), matching ZTE's clarification that tokenless deletion was test-environment only.

---

## Running the Probe

Prerequisites: **PowerShell 7 (`pwsh`)**

```powershell
pwsh -ExecutionPolicy Bypass -File .\Invoke-Runtime-AppAuth-AccountProbes.ps1
```
