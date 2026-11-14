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
plugins {
    id 'com.android.application' version '8.5.2'
    id 'com.google.gms.google-services' version '4.4.2'
}
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
    implementation platform('com.google.firebase:firebase-bom:33.5.1')
    implementation 'com.google.firebase:firebase-messaging'
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
        <service android:name=".FcmService" android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT" />
            </intent-filter>
        </service>
        <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="timedia" />
        <meta-data android:name="com.google.firebase.messaging.default_notification_icon" android:resource="@drawable/ic_notif" />
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
        loadUi();
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
        }
        NotifWorker.schedule(this);
    }

    // L'interface katji mn GitHub (release « app.html »): ay tabdil kayban bla ma n3awdo l'installation.
    static final String BASE = "https://app.timedia.local/";
    static final String UI_URL = "https://github.com/Timedia-app/timedia-mobile/releases/latest/download/app.html";

    private static String readAll(java.io.InputStream in) throws java.io.IOException {
        java.io.ByteArrayOutputStream b = new java.io.ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) b.write(buf, 0, n);
        in.close();
        return new String(b.toByteArray(), "UTF-8");
    }

    private void loadUi() {
        String html = null;
        final java.io.File cache = new java.io.File(getFilesDir(), "app.html");
        try { if (cache.exists()) html = readAll(new java.io.FileInputStream(cache)); } catch (Exception e) { html = null; }
        if (html == null) {
            try { html = readAll(getAssets().open("index.html")); } catch (Exception e) { html = "<p>Erreur</p>"; }
        }
        web.loadDataWithBaseURL(BASE, html, "text/html", "utf-8", null);
        final String current = html;
        new Thread(new Runnable() {
            public void run() {
                try {
                    java.net.HttpURLConnection h = (java.net.HttpURLConnection) new java.net.URL(UI_URL).openConnection();
                    h.setInstanceFollowRedirects(true);
                    h.setConnectTimeout(15000);
                    h.setReadTimeout(30000);
                    if (h.getResponseCode() != 200) return;
                    final String fresh = readAll(h.getInputStream());
                    if (fresh.length() < 20000 || fresh.indexOf("TIMEDIA") < 0 || fresh.equals(current)) return;
                    java.io.FileOutputStream o = new java.io.FileOutputStream(cache);
                    o.write(fresh.getBytes("UTF-8"));
                    o.close();
                    runOnUiThread(new Runnable() {
                        public void run() { web.loadDataWithBaseURL(BASE, fresh, "text/html", "utf-8", null); }
                    });
                } catch (Exception e) {
                    // ma kaynch internet: kanb9aw b l version li 3ndna
                }
            }
        }).start();
    }

    private boolean openExternal(Uri u) {
        if ("file".equals(u.getScheme())) return false;
        if (u.toString().startsWith(BASE)) return true;
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
            if (token != null && !token.isEmpty()) { NotifWorker.runNow(c); FcmService.register(c); }
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
            // Ila Firebase khddam (push dyal Google), ma nbanouhomch 2 merrat.
            if (!p.getBoolean("fcm", false)) {
                for (int i = 0; i < items.length(); i++) {
                    JSONObject it = items.getJSONObject(i);
                    show(c, it.getInt("id"), it.getString("titre"), it.getString("msg"));
                }
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
cat > android/app/src/main/java/com/timedia/app/FcmService.java <<'__TIMEDIA_EOF__'
package com.timedia.app;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;

import androidx.annotation.NonNull;

import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import org.json.JSONArray;
import org.json.JSONObject;

// Push dyal Google (Firebase): katwsel 7ta l'application msdouda, b7al WhatsApp.
public class FcmService extends FirebaseMessagingService {

    static void channel(Context c) {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
            nm.createNotificationChannel(new NotificationChannel("timedia", "TIMEDIA", NotificationManager.IMPORTANCE_HIGH));
        }
    }

    // Kanjibou l'adresse dyal had tilifon w kansifto l serveur (m3a session dyal li dakhel).
    static void register(final Context c) {
        channel(c);
        try {
            FirebaseMessaging.getInstance().getToken().addOnSuccessListener(t -> send(c, t));
        } catch (Exception e) { }
    }

    static void send(final Context c, final String fcm) {
        new Thread(() -> {
            try {
                SharedPreferences p = c.getSharedPreferences("timedia", 0);
                String token = p.getString("token", "");
                if (token.isEmpty() || fcm == null || fcm.isEmpty()) return;
                JSONArray args = new JSONArray();
                args.put(token);
                args.put(fcm);
                JSONObject body = new JSONObject();
                body.put("fn", "registerFcm");
                body.put("args", args);
                JSONObject res = new JSONObject(NotifWorker.post(body.toString()));
                if (res.optBoolean("ok")) p.edit().putBoolean("fcm", true).apply();
            } catch (Exception e) { }
        }).start();
    }

    @Override
    public void onNewToken(@NonNull String t) {
        send(getApplicationContext(), t);
    }

    // Ila l'application m7loula, Android ma kaybanch notification bo7do: kanbanoha 7na.
    @Override
    public void onMessageReceived(@NonNull RemoteMessage m) {
        String titre = "TIMEDIA", msg = "";
        if (m.getNotification() != null) {
            if (m.getNotification().getTitle() != null) titre = m.getNotification().getTitle();
            if (m.getNotification().getBody() != null) msg = m.getNotification().getBody();
        } else {
            if (m.getData().get("title") != null) titre = m.getData().get("title");
            if (m.getData().get("body") != null) msg = m.getData().get("body");
        }
        NotifWorker.show(getApplicationContext(), (int) (System.currentTimeMillis() % 100000), titre, msg);
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
if [ -z "$KEYSTORE_B64" ]; then echo "Secret KEYSTORE_B64 manquant (Settings > Secrets > Actions)"; exit 1; fi
printf '%s' "$KEYSTORE_B64" | base64 -d > android/app/timedia.jks
keytool -list -keystore android/app/timedia.jks -storepass timedia2026 | grep -q '1F:1A:E3:CE:B9:D3:1A:2F' || { echo "KEYSTORE_B64 ghalat (machi nafs tabe3)"; exit 1; }
cp google-services.json android/app/google-services.json
python3 android/patch_index.py Index.html android/app/src/main/assets/index.html
cp android/app/src/main/assets/index.html out/app.html
cd android
gradle assembleRelease --no-daemon --stacktrace
cp app/build/outputs/apk/release/app-release.apk ../out/TIMEDIA.apk
ls -la ../out
