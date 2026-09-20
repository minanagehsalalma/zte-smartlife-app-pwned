'use strict';

Java.perform(function () {
  var AesUtils = Java.use('com.zte.common.utils.AesUtils');
  var AppMainBackend = Java.use('com.zte.common.backend.AppMainBackend');

  function safeString(v) {
    try {
      if (v === null || v === undefined) {
        return '<null>';
      }
      return v.toString();
    } catch (e) {
      return '<error:' + e + '>';
    }
  }

  function currentAuthMaterial() {
    return [
      safeString(AppMainBackend.UAC_ACCOUNT_SEC_KEY.value),
      safeString(AppMainBackend.UAC_ACCOUNT_CLIENT_ID.value),
      safeString(AppMainBackend.UAC_ACCOUNT_ACCESS_KEY.value),
      Date.now().toString()
    ].join(',');
  }

  try {
    var aesGcmEncrypt = AesUtils.aesGcmEncrypt.overload('java.lang.String');
    aesGcmEncrypt.implementation = function (input) {
      var result = aesGcmEncrypt.call(this, input);
      console.log('');
      console.log('[aesGcmEncrypt]');
      console.log('input=' + safeString(input));
      console.log('result=' + safeString(result));
      return result;
    };
    console.log('[+] Hooked AesUtils.aesGcmEncrypt(String)');
  } catch (e) {
    console.log('[-] Failed to hook aesGcmEncrypt: ' + e);
  }

  rpc.exports = {
    getuac: function () {
      return {
        appUacUrl: safeString(AppMainBackend.UAC_ACCOUNT_SERVER_URL.value),
        appClientKey: safeString(AppMainBackend.UAC_ACCOUNT_CLIENT_KEY.value),
        appUacId: safeString(AppMainBackend.UAC_ACCOUNT_CLIENT_ID.value),
        appUacTenant: safeString(AppMainBackend.UAC_ACCOUNT_TENANT_ID.value),
        appUacSec: safeString(AppMainBackend.UAC_ACCOUNT_SEC_KEY.value),
        appUacItp: safeString(AppMainBackend.UAC_ACCOUNT_ACCESS_KEY.value)
      };
    },

    signauth: function () {
      var material = currentAuthMaterial();
      var authValue = AesUtils.aesGcmEncrypt(material);
      return {
        authMaterial: material,
        xAuthValue: safeString(authValue),
        xTenantId: safeString(AppMainBackend.UAC_ACCOUNT_TENANT_ID.value),
        xAppId: safeString(AppMainBackend.UAC_ACCOUNT_CLIENT_ID.value),
        xItpValue: 'accessKey=' + safeString(AppMainBackend.UAC_ACCOUNT_ACCESS_KEY.value)
      };
    },

    encryptpayload: function (plaintext) {
      return safeString(AesUtils.aesGcmEncrypt(plaintext));
    }
  };

  console.log('[*] smartlife_signing_oracle.js loaded');
  console.log('[*] RPC exports: getuac, signauth, encryptpayload');
});
