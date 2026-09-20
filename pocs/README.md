# Proof of Concept (PoC) Suites

This directory contains the minimal, standalone PoC tooling used to validate the ZTE SmartLife backend vulnerabilities (`CVE-2026-86552`, `CVE-2026-86553`, `CVE-2026-86554`, `CVE-2026-86555`).

All endpoints have been patched and key material rotated by ZTE. The scripts and keys below are published for security research and technical verification.

---

## Cryptographic Key Reference

| Parameter | Value | Role |
| :--- | :--- | :--- |
| **Bootstrap Decrypt Key (CVE-2026-86555)** | `096760a7a99d99d12de9fecbfca568c0` | AES-128-GCM key hardcoded in `AppMainBackend.setUacSignInfo` |
| **Client Symmetric Key (`appClientKey`)** | `djrom(&)(&)MORJD` | AES-128-GCM key used for `X-Auth-Value` signing and payload parameter encryption |
| **Shared Secret (`appUacSec`)** | `b2cfe28732612cfd81de7a22ace2034317a47eb94683a016a85cc0883597c625` | Embedded secret incorporated into timestamped `X-Auth-Value` tokens |
| **Access Key (`appUacItp`)** | `271950143414fnu4mb3lxxotfj5mi1tp` | Access key passed in `X-Itp-Value: accessKey=...` |
| **App / Client ID (`appId`)** | `271950143414` | Client system identifier |
| **Tenant ID (`tenantId`)** | `10001` | Cloud tenant identifier |

---

## Directory Overview

### 1. [`direct-replay/`](direct-replay/)
Contains [`account-takeover-poc.ps1`](direct-replay/account-takeover-poc.ps1), an automated PowerShell 7 script demonstrating:
- Public bootstrap payload decryption (`CVE-2026-86555`)
- Account enumeration and `accountId` disclosure (`CVE-2026-86554`)
- Password reset without verification code (`CVE-2026-86553`)
- Successful login postcondition with the attacker-set password
- Arbitrary email identity pre-registration / squatting (`CVE-2026-86552`)

### 2. [`frida/`](frida/)
Contains in-process runtime instrumentation scripts for the official Android client (`com.zte.smarthome.abroad`):
- [`smartlife_dump_uac.js`](frida/smartlife_dump_uac.js): Hooks client bootstrap decryption and dumps UAC configuration and outbound headers.
- [`smartlife_signing_oracle.js`](frida/smartlife_signing_oracle.js): Exposes Frida RPC methods to sign headers and encrypt payloads remotely via the app process.

### 3. [`runtime-path-probes/`](runtime-path-probes/)
Contains [`Invoke-Runtime-AppAuth-AccountProbes.ps1`](runtime-path-probes/Invoke-Runtime-AppAuth-AccountProbes.ps1), a standalone probe script verifying the active production backend (`https://zxuacde.smart-zte.com`) using recovered credentials.

---

## Quick Start

### Run Direct Replay PoC (PowerShell 7)
```powershell
cd direct-replay
pwsh -ExecutionPolicy Bypass -File .\account-takeover-poc.ps1
```

### Run Production Path Probe (PowerShell 7)
```powershell
cd runtime-path-probes
pwsh -ExecutionPolicy Bypass -File .\Invoke-Runtime-AppAuth-AccountProbes.ps1
```

### Hook Live App with Frida
```bash
cd frida
frida -U -f com.zte.smarthome.abroad -l smartlife_dump_uac.js
```
