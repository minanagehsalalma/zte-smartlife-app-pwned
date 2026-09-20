# ZTE SmartLife Security Findings Leading to Account Takeover

Technical write-up and supporting material for a ZTE SmartLife account-backend investigation.

**Read the article:** [ZTE Smarthome TakeOver](index.html)  
**Researcher:** [Mina Nageh Salama](https://www.linkedin.com/in/minanagehzekry)

## What happened

The public SmartLife Android client exposed enough application-authentication material for requests to reach the account backend. Several account flows then accepted application context where they needed user-level verification.

The most significant result was a password-reset path that accepted a new password without a reset code. Login with the new password then succeeded, producing account takeover on the validated proof account.

The research was coordinated with ZTE PSIRT. ZTE patched the affected paths and assigned four CVEs.

The affected Android app had **100K+ Google Play downloads** at the time of publication; Apple does not publish an equivalent install count.

## CVEs

| CVE | Finding | ZTE score |
| --- | --- | ---: |
| [CVE-2026-86553](https://support.zte.com.cn/zte-iccp-isupport-webui/bulletin/detail/2171542593031840100) | Password reset without verification code | 8.8 High |
| [CVE-2026-86555](https://support.zte.com.cn/zte-iccp-isupport-webui/bulletin/detail/874505866159007054) | Hardcoded SmartLife application key | 6.2 Medium |
| [CVE-2026-86554](https://support.zte.com.cn/zte-iccp-isupport-webui/bulletin/detail/2171542593031840113) | Email enumeration and account ID disclosure | 4.3 Medium |
| [CVE-2026-86552](https://support.zte.com.cn/zte-iccp-isupport-webui/bulletin/detail/460174866982102946) | Email ownership verification bypass during registration | 5.4 Medium |

ZTE assessed the earlier tokenless account-deletion behavior as test-environment-only; the current production path requires a token and was not assigned a CVE.

## Repository map

- [`index.html`](index.html) - full technical article with the attack flow, request shapes, runtime path, SDK surface, advisories, and timeline.
- [`pocs/README.md`](pocs/README.md) - overview of the reproduction material.
- [`pocs/direct-replay/`](pocs/direct-replay/) - direct account-lifecycle replay workflow.
- [`pocs/frida/`](pocs/frida/) - runtime observation of the official Android client.
- [`pocs/runtime-path-probes/`](pocs/runtime-path-probes/) - current runtime-host and endpoint behavior checks.
- [`writeup-assets/`](writeup-assets/) - article assets.

## PoC methods

### Direct replay

Reconstructs the application-auth context and exercises the account lifecycle with researcher-controlled proof accounts. The useful postconditions are account creation, account lookup, password replacement, and login with the replacement password.

### Frida runtime observation

Attaches to the official client process and records the runtime-selected account backend and in-process request-signing path. This provides an independent view of how the public app reaches the API.

### Runtime-path retest

Checks the current public-client host and separates the earlier test-environment deletion behavior from the production account findings.

## Start here

1. Read the [article](index.html).
2. Review the [PoC overview](pocs/README.md).
3. Use the method-specific README files for setup and evidence layout.

## Status

The findings were disclosed to ZTE PSIRT under coordinated disclosure. The affected vulnerabilities were patched, four CVEs were assigned, and the vendor advisories are linked above.
