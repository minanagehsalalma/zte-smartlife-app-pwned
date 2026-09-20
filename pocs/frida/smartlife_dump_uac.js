'use strict';

/**
 * SmartLife Frida UAC & Header Extraction Script
 *
 * Hooks:
 * 1. AppMainBackend.setUacSignInfo: Captures decrypted UAC config & keys.
 * 2. HttpsPost: Intercepts account requests and empNo tokens.
 * 3. URLConnection.setRequestProperty: Captures generated account authentication headers.
 *
 * Usage:
 *   frida -U -f com.zte.smarthome.abroad -l smartlife_dump_uac.js
 */

Java.perform(function () {
  var AppMainBackend = Java.use('com.zte.common.backend.AppMainBackend');
  var HttpsPost = Java.use('com.zte.smarthome.account.http.HttpsPost');
  var URLConnection = Java.use('java.net.URLConnection');

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

  function dumpUac(label) {
    try {
      console.log('');
      console.log('=== ' + label + ' ===');
      console.log('UAC_ACCOUNT_SERVER_URL=' + safeString(AppMainBackend.UAC_ACCOUNT_SERVER_URL.value));
      console.log('UAC_ACCOUNT_CLIENT_KEY=' + safeString(AppMainBackend.UAC_ACCOUNT_CLIENT_KEY.value));
      console.log('UAC_ACCOUNT_CLIENT_ID=' + safeString(AppMainBackend.UAC_ACCOUNT_CLIENT_ID.value));
      console.log('UAC_ACCOUNT_TENANT_ID=' + safeString(AppMainBackend.UAC_ACCOUNT_TENANT_ID.value));
      console.log('UAC_ACCOUNT_SEC_KEY=' + safeString(AppMainBackend.UAC_ACCOUNT_SEC_KEY.value));
      console.log('UAC_ACCOUNT_ACCESS_KEY=' + safeString(AppMainBackend.UAC_ACCOUNT_ACCESS_KEY.value));
    } catch (e) {
      console.log('dumpUac error: ' + e);
    }
  }

  // Hook bootstrap decrypt method
  try {
    var setUacSignInfo = AppMainBackend.setUacSignInfo.overload('java.lang.String');
    setUacSignInfo.implementation = function (blob) {
      console.log('');
      console.log('[setUacSignInfo] Encrypted bootstrap blob=' + safeString(blob));
      var result = setUacSignInfo.call(this, blob);
      dumpUac('POST-DECRYPT RUNTIME UAC');
      return result;
    };
    console.log('[+] Hooked AppMainBackend.setUacSignInfo(String)');
  } catch (e) {
    console.log('[-] Failed to hook setUacSignInfo: ' + e);
  }

  // Hook HttpsPost request constructor
  try {
    var ctor1 = HttpsPost.$init.overload('java.util.Properties', 'java.lang.String', 'java.lang.String');
    ctor1.implementation = function (props, url, body) {
      console.log('');
      console.log('[HttpsPost] URL=' + safeString(url));
      console.log('[HttpsPost] Body=' + safeString(body));
      dumpUac('UAC STATE BEFORE REQUEST');
      return ctor1.call(this, props, url, body);
    };
    console.log('[+] Hooked HttpsPost(Properties, String, String)');
  } catch (e) {
    console.log('[-] Failed to hook HttpsPost ctor1: ' + e);
  }

  // Hook outbound headers
  try {
    var setRequestProperty = URLConnection.setRequestProperty.overload('java.lang.String', 'java.lang.String');
    setRequestProperty.implementation = function (key, value) {
      var k = safeString(key);
      if (k === 'X-Auth-Value' || k === 'X-Tenant-Id' || k === 'X-App-Id' || k === 'X-Itp-Value' || k === 'X-Emp-No') {
        console.log('[Header] ' + k + '=' + safeString(value));
      }
      return setRequestProperty.call(this, key, value);
    };
    console.log('[+] Hooked URLConnection.setRequestProperty(String, String)');
  } catch (e) {
    console.log('[-] Failed to hook URLConnection.setRequestProperty: ' + e);
  }

  console.log('[*] smartlife_dump_uac.js loaded.');
});
