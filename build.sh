#!/bin/bash
# TIMEDIA — kaybni l'application Android. Index.html = nafs l'interface dyal Apps Script.
set -e
rm -rf android out
mkdir -p android/app/src/main/java/com/timedia/app android/app/src/main/assets android/app/src/main/res/drawable out
cat > android/settings.gradle <<'__TIMEDIA_EOF__'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = 'timedia'
include ':app'
__TIMEDIA_EOF__
cat > android/gradle.properties <<'__TIMEDIA_EOF__'
android.useAndroidX=true
org.gradle.jvmargs=-Xmx2g
__TIMEDIA_EOF__
cat > android/app/build.gradle <<'__TIMEDIA_EOF__'
plugins { id 'com.android.application' version '8.5.2' }
android {
    namespace 'com.timedia.app'
    compileSdk 34
    defaultConfig {
        applicationId 'com.timedia.app'
        minSdk 24
        targetSdk 34
        versionCode Integer.parseInt(System.getenv('GITHUB_RUN_NUMBER') ?: '1')
        versionName '1.' + (System.getenv('GITHUB_RUN_NUMBER') ?: '0')
    }
    signingConfigs {
        rel { storeFile file('timedia.jks'); storePassword 'timedia2026'; keyAlias 'timedia'; keyPassword 'timedia2026' }
    }
    buildTypes { release { minifyEnabled false; signingConfig signingConfigs.rel } }
    compileOptions { sourceCompatibility JavaVersion.VERSION_17; targetCompatibility JavaVersion.VERSION_17 }
}
dependencies {
    implementation 'androidx.work:work-runtime:2.9.1'
    implementation 'androidx.core:core:1.13.1'
}
__TIMEDIA_EOF__
cat > android/app/src/main/AndroidManifest.xml <<'__TIMEDIA_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <application
        android:label="TIMEDIA"
        android:icon="@drawable/ic_launcher"
        android:theme="@android:style/Theme.Material.Light.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTask"
            android:configChanges="orientation|screenSize|keyboardHidden"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
__TIMEDIA_EOF__
cat > android/app/src/main/java/com/timedia/app/MainActivity.java <<'__TIMEDIA_EOF__'
package com.timedia.app;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

public class MainActivity extends Activity {
    private WebView web;
    private ValueCallback<Uri[]> fileCb;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().setStatusBarColor(Color.parseColor("#D7263D"));
        web = new WebView(this);
        setContentView(web);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        s.setAllowFileAccessFromFileURLs(true);
        s.setAllowUniversalAccessFromFileURLs(true);
        s.setJavaScriptCanOpenWindowsAutomatically(true);
        web.addJavascriptInterface(new Bridge(this), "Android");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                return openExternal(r.getUrl());
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView v, ValueCallback<Uri[]> cb, FileChooserParams p) {
                if (fileCb != null) fileCb.onReceiveValue(null);
                fileCb = cb;
                Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType("image/*");
                try {
                    startActivityForResult(Intent.createChooser(i, "Reçu"), 7);
                } catch (Exception e) {
                    fileCb = null;
                    return false;
                }
                return true;
            }
        });
        web.loadUrl("file:///android_asset/index.html");
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
        }
        NotifWorker.schedule(this);
    }

    private boolean openExternal(Uri u) {
        if ("file".equals(u.getScheme())) return false;
        try {
            Intent i = new Intent(Intent.ACTION_VIEW, u);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (Exception e) {
            // ma kayn 7ta application t7el had l lien
        }
        return true;
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req == 7 && fileCb != null) {
            fileCb.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(res, data));
            fileCb = null;
        }
    }

    @Override
    public void onBackPressed() {
        if (web.canGoBack()) web.goBack();
        else super.onBackPressed();
    }

    static class Bridge {
        private final Context c;
        private final MainActivity a;

        Bridge(MainActivity a) {
            this.a = a;
            this.c = a.getApplicationContext();
        }

        @JavascriptInterface
        public void setToken(String token, String role) {
            c.getSharedPreferences("timedia", 0).edit()
                .putString("token", token == null ? "" : token).putInt("last", 0).apply();
            if (token != null && !token.isEmpty()) NotifWorker.runNow(c);
        }

        @JavascriptInterface
        public void openUrl(final String url) {
            a.runOnUiThread(new Runnable() {
                public void run() { a.openExternal(Uri.parse(url)); }
            });
        }
    }
}
__TIMEDIA_EOF__
cat > android/app/src/main/java/com/timedia/app/NotifWorker.java <<'__TIMEDIA_EOF__'
package com.timedia.app;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.OneTimeWorkRequest;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

// Kol 15 d9i9a: katsoul l serveur wach kayna notification jdida, w katbanha f tilifon.
public class NotifWorker extends Worker {
    static final String API = "https://script.google.com/macros/s/AKfycbyA1MX1tBYkeR_MLt_jPVBFHYS5J-79QQBObwZXI6JVXhw10wCHP27jd3tHbDChkwgVfw/exec";

    public NotifWorker(@NonNull Context c, @NonNull WorkerParameters p) {
        super(c, p);
    }

    static void schedule(Context c) {
        Constraints k = new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build();
        PeriodicWorkRequest w = new PeriodicWorkRequest.Builder(NotifWorker.class, 15, TimeUnit.MINUTES).setConstraints(k).build();
        WorkManager.getInstance(c).enqueueUniquePeriodicWork("timedia-notifs", ExistingPeriodicWorkPolicy.KEEP, w);
    }

    static void runNow(Context c) {
        WorkManager.getInstance(c).enqueue(new OneTimeWorkRequest.Builder(NotifWorker.class).build());
    }

    @NonNull
    @Override
    public Result doWork() {
        Context c = getApplicationContext();
        SharedPreferences p = c.getSharedPreferences("timedia", 0);
        String token = p.getString("token", "");
        if (token.isEmpty()) return Result.success();
        try {
            JSONArray args = new JSONArray();
            args.put(token);
            args.put(p.getInt("last", 0));
            JSONObject body = new JSONObject();
            body.put("fn", "pollNotifs");
            body.put("args", args);
            JSONObject res = new JSONObject(post(body.toString()));
            if (!res.optBoolean("ok")) {
                if ("SESSION".equals(res.optString("error"))) p.edit().putString("token", "").apply();
                return Result.success();
            }
            JSONObject d = res.getJSONObject("data");
            JSONArray items = d.getJSONArray("items");
            for (int i = 0; i < items.length(); i++) {
                JSONObject it = items.getJSONObject(i);
                show(c, it.getInt("id"), it.getString("titre"), it.getString("msg"));
            }
            p.edit().putInt("last", d.getInt("last")).apply();
            return Result.success();
        } catch (Exception e) {
            return Result.retry();
        }
    }

    static String post(String json) throws IOException {
        HttpURLConnection h = (HttpURLConnection) new URL(API).openConnection();
        h.setRequestMethod("POST");
        h.setDoOutput(true);
        h.setInstanceFollowRedirects(false);
        h.setConnectTimeout(20000);
        h.setReadTimeout(60000);
        h.setRequestProperty("Content-Type", "text/plain;charset=utf-8");
        try (OutputStream o = h.getOutputStream()) {
            o.write(json.getBytes(StandardCharsets.UTF_8));
        }
        int code = h.getResponseCode();
        if (code >= 300 && code < 400) {
            String loc = h.getHeaderField("Location");
            h.disconnect();
            h = (HttpURLConnection) new URL(loc).openConnection();
            h.setConnectTimeout(20000);
            h.setReadTimeout(60000);
        }
        try (InputStream in = h.getInputStream(); ByteArrayOutputStream b = new ByteArrayOutputStream()) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) b.write(buf, 0, n);
            return new String(b.toByteArray(), StandardCharsets.UTF_8);
        }
    }

    static void show(Context c, int id, String titre, String msg) {
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(new NotificationChannel("timedia", "TIMEDIA", NotificationManager.IMPORTANCE_HIGH));
        }
        Intent i = new Intent(c, MainActivity.class);
        i.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pi = PendingIntent.getActivity(c, 0, i, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        NotificationCompat.Builder b = new NotificationCompat.Builder(c, "timedia")
            .setSmallIcon(R.drawable.ic_notif)
            .setContentTitle(titre)
            .setContentText(msg)
            .setStyle(new NotificationCompat.BigTextStyle().bigText(msg))
            .setAutoCancel(true)
            .setContentIntent(pi)
            .setPriority(NotificationCompat.PRIORITY_HIGH);
        try {
            nm.notify(id, b.build());
        } catch (SecurityException e) {
            // notifications ma m7loulinch
        }
    }
}
__TIMEDIA_EOF__
cat > android/app/src/main/res/drawable/ic_launcher.xml <<'__TIMEDIA_EOF__'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#D7263D" android:pathData="M24,0h60a24,24 0 0 1 24,24v60a24,24 0 0 1 -24,24h-60a24,24 0 0 1 -24,-24v-60a24,24 0 0 1 24,-24z" />
    <path android:fillColor="#FFFFFF" android:pathData="M28,26h52v13h-19.5v45h-13v-45h-19.5z" />
</vector>
__TIMEDIA_EOF__
cat > android/app/src/main/res/drawable/ic_notif.xml <<'__TIMEDIA_EOF__'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#FFFFFF" android:pathData="M18,14h72v18h-27v62h-18v-62h-27z" />
</vector>
__TIMEDIA_EOF__
cat > android/patch_index.py <<'__TIMEDIA_EOF__'
# Kaybeddel Index.html (dyal Apps Script) l version dyal l'application Android.
import sys
API = 'https://script.google.com/macros/s/AKfycbyA1MX1tBYkeR_MLt_jPVBFHYS5J-79QQBObwZXI6JVXhw10wCHP27jd3tHbDChkwgVfw/exec'
s = open(sys.argv[1], encoding='utf-8').read()
def rep(o, n):
    global s
    if s.count(o) != 1: raise SystemExit('patch failed: ' + o[:60])
    s = s.replace(o, n)
rep('<base target="_top">\n', '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n')
a = s.index('function call(fn) {'); b = s.index('\n}\n', a) + 3
s = s[:a] + """var API = '%s';
function call(fn) {
  var args = Array.prototype.slice.call(arguments, 1);
  return fetch(API, { method: 'POST', body: JSON.stringify({ fn: fn, args: args }) })
    .then(function (r) { return r.json(); }, function () { throw new Error('Ma kaynch internet. 3awdi mn b3d.'); })
    .then(function (r) {
      if (r.ok) return r.data;
      if (String(r.error).indexOf('SESSION') >= 0) { logoutLocal(); throw new Error('Session sallat, dkhli 3awtani.'); }
      throw new Error(r.error);
    });
}
if (window.Android) window.open = function (u) { Android.openUrl(u); return null; };
function nativeToken() { try { if (window.Android) Android.setToken(S.token || '', S.role || ''); } catch (e) {} }
""" % API + s[b:]
rep("function logoutLocal() { S.token = null; try { localStorage.removeItem('timedia_session'); } catch (e) {} renderLogin(); }",
    "function logoutLocal() { S.token = null; try { localStorage.removeItem('timedia_session'); } catch (e) {} nativeToken(); renderLogin(); }")
rep("    S.refs = r; $('who')", "    S.refs = r; nativeToken(); $('who')")
open(sys.argv[2], 'w', encoding='utf-8').write(s)
print('index ok', len(s))
__TIMEDIA_EOF__
base64 -d > android/app/timedia.jks <<'__TIMEDIA_EOF__'
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
Rwfa/YUxLdoCAicQ
__TIMEDIA_EOF__
python3 android/patch_index.py Index.html android/app/src/main/assets/index.html
cd android
gradle assembleRelease --no-daemon --stacktrace
cp app/build/outputs/apk/release/app-release.apk ../out/TIMEDIA.apk
ls -la ../out
