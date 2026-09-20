# Frida Runtime Instrumentation

This folder contains the core Frida hooks used to observe the official Android app (`com.zte.smarthome.abroad`) in-process and demonstrate client-side trust recovery and header generation.

---

## Included Files

- **`smartlife_dump_uac.js`**: Consolidated Frida hook intercepting `AppMainBackend.setUacSignInfo`, `HttpsPost`, and `URLConnection.setRequestProperty`. Dumps decrypted bootstrap configuration and outbound signed account headers.
- **`smartlife_signing_oracle.js`**: Exposes Frida RPC exports (`getuac`, `signauth`, `encryptpayload`), enabling remote signature computation and payload encryption directly via the app process.

---

## Live Observed Runtime Values

Instrumentation of `com.zte.smarthome.abroad` extracts the following values directly from client memory:

```text
UAC_ACCOUNT_SERVER_URL=https://zxuacde.smart-zte.com
UAC_ACCOUNT_CLIENT_KEY=djrom(&)(&)MORJD
UAC_ACCOUNT_CLIENT_ID=271950143414
UAC_ACCOUNT_TENANT_ID=10001
UAC_ACCOUNT_SEC_KEY=b2cfe28732612cfd81de7a22ace2034317a47eb94683a016a85cc0883597c625
UAC_ACCOUNT_ACCESS_KEY=271950143414fnu4mb3lxxotfj5mi1tp
```

Outbound signed header structure:

```text
X-App-Id: 271950143414
X-Tenant-Id: 10001
X-Itp-Value: accessKey=271950143414fnu4mb3lxxotfj5mi1tp
X-Auth-Value: <fresh AES-GCM ciphertext encrypted with djrom(&)(&)MORJD>
```

---

## Running the Hooks

With `frida-server` running on an attached device or emulator:

### Capture Runtime Keys and Outbound Headers
```bash
frida -U -f com.zte.smarthome.abroad -l smartlife_dump_uac.js
```

### Use App as a Signing Oracle
```bash
frida -U com.zte.smarthome.abroad -l smartlife_signing_oracle.js
```
