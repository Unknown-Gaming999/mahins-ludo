===== FILE: .gitignore =====
build/
.dart_tool/
android/
functions/node_modules/
hosting/public/MahinsLudo.apk
*.iml
.idea/

===== FILE: pubspec.yaml =====
name: ludo
description: Mahin's Ludo - online multiplayer Ludo
publish_to: "none"
version: 1.0.0+1

environment:
  sdk: ">=3.4.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  firebase_core: ">=3.8.0 <3.11.0"
  firebase_auth: ">=5.3.3 <5.5.0"
  firebase_database: ">=11.1.4 <11.4.0"
  cloud_functions: ">=5.1.4 <5.4.0"
  share_plus: ^10.1.0
  app_links: ^6.3.0
  shared_preferences: ^2.3.0
  url_launcher: ^6.3.0

flutter:
  uses-material-design: true

===== FILE: firebase.json =====
{
  "database": { "rules": "database.rules.json" },
  "functions": [
    { "source": "functions", "codebase": "default", "runtime": "nodejs20" }
  ],
  "hosting": {
    "public": "hosting/public",
    "ignore": ["firebase.json", "**/node_modules/**"],
    "rewrites": [{ "source": "/join/**", "destination": "/join.html" }],
    "headers": [
      {
        "source": "/.well-known/assetlinks.json",
        "headers": [{ "key": "Content-Type", "value": "application/json" }]
      },
      {
        "source": "**/*.apk",
        "headers": [
          { "key": "Content-Type", "value": "application/vnd.android.package-archive" },
          { "key": "Content-Disposition", "value": "attachment; filename=\"MahinsLudo.apk\"" }
        ]
      }
    ]
  }
}

===== FILE: database.rules.json =====
{
  "rules": {
    ".read": false,
    ".write": false,
    "users": {
      "$uid": {
        ".read": "auth != null && auth.uid === $uid",
        ".write": "auth != null && auth.uid === $uid",
        ".validate": "newData.hasChildren(['name', 'avatar'])",
        "name": { ".validate": "newData.isString() && newData.val().length >= 1 && newData.val().length <= 16" },
        "avatar": { ".validate": "newData.isNumber() && newData.val() >= 0 && newData.val() < 12" },
        "$other": { ".validate": false }
      }
    },
    "stats": {
      "$uid": {
        ".read": "auth != null && auth.uid === $uid",
        ".write": false
      }
    },
    "rooms": {
      ".indexOn": ["createdAt", "isPublic"],
      "$code": {
        ".read": "auth != null",
        "players": {
          "$uid": {
            "connected": {
              ".write": "auth != null && auth.uid === $uid && data.parent().exists()",
              ".validate": "newData.isBoolean()"
            },
            "lastSeen": {
              ".write": "auth != null && auth.uid === $uid && data.parent().exists()",
              ".validate": "newData.isNumber()"
            }
          }
        }
      }
    }
  }
}

===== FILE: .github/workflows/build-apk.yml =====
name: Build APK

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 45
    env:
      GOOGLE_SERVICES_JSON: ${{ secrets.GOOGLE_SERVICES_JSON }}
      FIREBASE_PROJECT_ID: ${{ secrets.FIREBASE_PROJECT_ID }}
      DATABASE_URL: ${{ secrets.DATABASE_URL }}
      FIREBASE_SERVICE_ACCOUNT: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
    steps:
      - uses: actions/checkout@v4

      - name: Check required secrets
        run: |
          [ -n "$GOOGLE_SERVICES_JSON" ] || { echo "::error::Missing secret GOOGLE_SERVICES_JSON"; exit 1; }
          [ -n "$FIREBASE_PROJECT_ID" ] || { echo "::error::Missing secret FIREBASE_PROJECT_ID"; exit 1; }

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: "3.27.4"
          channel: stable
          cache: true

      - name: Generate and configure Android project
        run: |
          flutter create --org com.mahin --project-name ludo --platforms android /tmp/scaffold
          cp -r /tmp/scaffold/android ./android
          cp -r android_overrides/app/. android/app/
          sed -i "s/__HOSTING_DOMAIN__/${FIREBASE_PROJECT_ID}.web.app/g" android/app/src/main/AndroidManifest.xml
          printf '%s' "$GOOGLE_SERVICES_JSON" > android/app/google-services.json
          python3 tools/patch_android.py
          pip install pillow
          python3 tools/make_icons.py android/app/src/main/res
          mkdir -p ~/.android
          base64 -d android_overrides/debug.keystore.b64 > ~/.android/debug.keystore
          echo "Signing certificate fingerprint:"
          keytool -list -v -keystore ~/.android/debug.keystore -storepass android | grep SHA256

      - run: flutter pub get

      - name: Build release APK
        run: |
          flutter build apk --release \
            --dart-define=HOSTING_DOMAIN=${FIREBASE_PROJECT_ID}.web.app \
            --dart-define=DATABASE_URL=${DATABASE_URL}

      - name: Rename APK
        run: cp build/app/outputs/flutter-apk/app-release.apk MahinsLudo.apk

      - uses: actions/upload-artifact@v4
        with:
          name: MahinsLudo-apk
          path: MahinsLudo.apk

      - name: Publish APK to the download page (only if service account secret exists)
        if: env.FIREBASE_SERVICE_ACCOUNT != ''
        run: |
          cp MahinsLudo.apk hosting/public/MahinsLudo.apk
          printf '%s' "$FIREBASE_SERVICE_ACCOUNT" > /tmp/sa.json
          export GOOGLE_APPLICATION_CREDENTIALS=/tmp/sa.json
          npx --yes firebase-tools@13 deploy --only hosting --project "$FIREBASE_PROJECT_ID" --non-interactive

===== FILE: .github/workflows/deploy-backend.yml =====
name: Deploy Firebase backend

on:
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    env:
      FIREBASE_PROJECT_ID: ${{ secrets.FIREBASE_PROJECT_ID }}
      FIREBASE_SERVICE_ACCOUNT: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
    steps:
      - uses: actions/checkout@v4
      - name: Check secrets
        run: |
          [ -n "$FIREBASE_PROJECT_ID" ] || { echo "::error::Missing secret FIREBASE_PROJECT_ID"; exit 1; }
          [ -n "$FIREBASE_SERVICE_ACCOUNT" ] || { echo "::error::Missing secret FIREBASE_SERVICE_ACCOUNT"; exit 1; }
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
      - name: Deploy database rules, functions and hosting
        run: |
          printf '%s' "$FIREBASE_SERVICE_ACCOUNT" > /tmp/sa.json
          export GOOGLE_APPLICATION_CREDENTIALS=/tmp/sa.json
          npx --yes firebase-tools@13 deploy --only database,functions,hosting --project "$FIREBASE_PROJECT_ID" --non-interactive

===== FILE: android_overrides/app/src/main/AndroidManifest.xml =====
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.VIBRATE"/>

    <application
        android:label="@string/app_name"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:screenOrientation="portrait"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme"/>
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="https" android:host="__HOSTING_DOMAIN__" android:pathPrefix="/join"/>
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="mahinsludo" android:host="join"/>
            </intent-filter>
        </activity>
        <meta-data android:name="flutterEmbedding" android:value="2"/>
        <meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>
    </application>

    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
        <package android:name="com.whatsapp"/>
    </queries>
</manifest>

===== FILE: android_overrides/app/src/main/res/values/strings.xml =====
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Mahin\'s Ludo</string>
</resources>

===== FILE: android_overrides/app/src/main/res/drawable/launch_background.xml =====
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <shape android:shape="rectangle">
            <solid android:color="#2B1A6E"/>
        </shape>
    </item>
    <item>
        <bitmap android:gravity="center" android:src="@drawable/splash_logo"/>
    </item>
</layer-list>

===== FILE: android_overrides/debug.keystore.b64 =====
MIIKdgIBAzCCCiAGCSqGSIb3DQEHAaCCChEEggoNMIIKCTCCBbAGCSqGSIb3DQEHAaCCBaEEggWd
MIIFmTCCBZUGCyqGSIb3DQEMCgECoIIFMDCCBSwwZgYJKoZIhvcNAQUNMFkwOAYJKoZIhvcNAQUM
MCsEFMM7nJSgptYNTtideLFQ5R4jnAgIAgInEAIBIDAMBggqhkiG9w0CCQUAMB0GCWCGSAFlAwQB
KgQQ6NTn9qMBuI9YItdgi0T/KASCBMAlRqEcIYBJPSi0vdbFXa29S0ph0c9BLTUWMFPAb6IMXxpV
eHgmJbLpbUSWDVprrLocs40vAnJgaOYC9orjYKjvm4qJ4STJl1eFsha172+P2KwJBEtBS7rcK6+K
jm1J/qfguBlSQaKPhI2qkz+8Lo8MMLGs8YPlwyWRSVFhVrY0/08q7XWxIsvpS3Jc9LakTWtxtnl5
9hE3tRdE053cQMMgj75JiMOLrR0vGIg1hVGaA2AEBAWaVMBhs/QOmXcBpIjXNju9YV1edE2lSDkQ
i8+6dwyGLcajMlSbJknkTbf0Gy7Q3n+h7gG22dFqdz6r58wAn2IqpEz/4vRZdjTW5xjfGaCD9vuL
lzWkev8EouAgXN5udXnTf7sC2saN9LxoAmOpgXxy2HPM3Q5agzzx99vNYFpfLkPJOj9Nsd9VQTko
n8OV5sBwpfrf6JjIOHTuIfDhMApDvwBhOwRzHKv8L4Q+EdRDIwPHF3MYoTF4IHMsf4nbqpo5n7xC
z48bbJuUmFE0BLIdXu8qUoFL5Bsj/vLZwRQrCUzxK0VOM1T4uFbYWIffCgGNhjuKYE77ZgcnW0CD
yApqOchdSpmKTEXY0ZZoJL/rxpAyzGecwMhBhm9p5WC/O9f60tNi+3sfcN264U4DOhXdtaqEV7ps
fngibfGbYgKKitKCJHAyz/bQ/oCYAvq08+QfoEduoPpqNs0RPJt6Wki0YeMR6Jd+bcHmn3riDLDj
TWq04nE0TCpPmgkJWDMqsY3jsgrEs2QogrE3B1Joq58gnLsCvMGne3i3Im7/p015YSoDJq39OkX0
0cMUClRL0ba+VaA17HgXMmo2uF/K3PtJn2rv9+n+luUkEzqz/hpZbd6+MC4cSvEQ7opRNaAG9Ap+
Ch1rgWSPXkH/eXmvYyMMcqWnXWIQVKcZaSzIP/DVSBcoOIebAq6icT7TBOWo0iIijT6Hu/66ah/H
qkIG3/UFiAsnRNme20IDiXMSquvk1lY8oK2ig837LabCrZ9PSOk9NtmybVytLOOhrsO0MEvrleng
Sg5fF4//u7BoVARkKcDKWJRBYbW5t4jvRf+CfzwLwg6igOo/SeThOjsxgQPOIs3lOtqO9ixddh5o
CaiSAtwaquHg7haWuRd9qdBB15M0tCIACA7g2AWtquk4eU9KVtapCHKnDdIn310cIo3DtOrhoyAc
cYuf28eOO8d/bIhLE7CQJqlJnMREmV0oiSRIyGCYqODd7iLDq3AAop7zVR6AdR51nKbntwHdGEGG
+SF12Wa/Mfs74Y8JlF3CylCMg9USDJSkMTbIYAa60iiydeEAJ48bq354jaLhNOJ0cgfS2du8ibDh
rtvvZjk3FN7Dgc2jw5a8IHrD9CRrsxa6gg9QDQpmBxGnf/Hj5f4OsF4FnDGLXGhVdJZ58doctto9
q6VWqSKnmefKWQK/lG/P+plyiYsJ4Loj7TLuBuhKPcnzL/zI+sT2RFeiboJLmMrKBU45SHfFLUzk
Q+IPRCA8RGEjW5+FjrhrSgTBlUJJHqa74awSwCaZvv+Tn8dbgIhxj7onQTFEzF+0ROzbg7xW5PPn
UTkHZNUmPuxLZm6ZsMjJT9+pj8CchAIRpZAtFEvOjwLDq6sQMZE60wipMVIwLQYJKoZIhvcNAQkU
MSAeHgBhAG4AZAByAG8AaQBkAGQAZQBiAHUAZwBrAGUAeTAhBgkqhkiG9w0BCRUxFAQSVGltZSAx
Nzk0ODM1NTY2MTgyMIIEUQYJKoZIhvcNAQcGoIIEQjCCBD4CAQAwggQ3BgkqhkiG9w0BBwEwZgYJ
KoZIhvcNAQUNMFkwOAYJKoZIhvcNAQUMMCsEFLFkSSkK1LuCXKSmKwrmj/Ys1UusAgInEAIBIDAM
BggqhkiG9w0CCQUAMB0GCWCGSAFlAwQBKgQQ99A/ylDRzgoaU2Zs7WYSpYCCA8A4vfz0Bm1gVEZl
7HJqWHWdLAPr7GnBVQlskHWHUBVTPuFCLgYXafj5wjmXu+by/UMpY82Vvx3X4hJ+s5CQ5CiM/sho
xmXAOq72lMxB2MnSQQ5V+tVlNHtJFw0aB927e5edRNUcsrzYCGcCbObR1C7WK3VDTSx4BqAlPksY
C1S6EkH4eHXmFl6Ny96NUFnHGWc+f1fIoiFbC5HTTys93CewgrV59FWE8MhcYdmC9xUeNN51fKi1
mb18/DAeK27SSC9WKRvGD7NlFz9sxV1N2nGmvQHz84+z3jhZzuODWxpFQ6YLvkYyM8ygmXi46zUi
U+rW0CtCHM9okSfuY69ZMDEtUefPSJQfepwGSe7a/6FLt5TLsx+1p+jPhEoWv6dWEoHNiV2bKv6F
1GXiBKp4692OaFwlewX2SpoaUCwhmOCQEmZSCptidKkJSnM+ZomKJjxfNHovbIyUDPbwwez8jJBb
YuntyjwPoeBwczfv3IZ/8b0pAz6mvKy6t4W6/Lx/rQKaHaxf9fBtCXW+9QpvwYBYwuv/8GMjZjmK
DyR8JXDZoo1KlpAM1YoAoi/IdH2vcAZhCTQu9gKdL5KUdFDuXkewiZOd1rkQIKsU9lm5aU37bE1K
2ZM83pt4eawlexVLPbE0fmpLNPTUIs5eVMnzz+gHnT6DqSNLavl8GjbQ9eDXcBVUgEiBSkWoVqS/
ti14ZN9GR+lO0ehImrr9cWwaf56F89ArF95/fgFShN6KhWnJ/Z0uz4066QW7tahrnLyD0yyOFsfk
Gfd3kNEBfph7j6+9aCQ0Fs1L127QUF0HPUwyXCEkgYP696BrGybrgquNzeQXlP2RMPWaje/CctqU
sp1jP0F5h/oN7AttumFlgW7IB/EbMfpmXhy1BsTJK7x/6mzOfTLI6geZgsqlulxyoXtXtj3kXa23
jKJyN2watsTujsgVvPYVWnhagWXPqShwzUrKNtTkVPL9Q2Am2lvWkOSVO/rOD4CEHyOP1ZC5AxE/
iKd989qgmvUNLZd9ggkIgzaJPUp+7JA3ehX05SruJBJToFK9/ZFB+3B8Yre7h9recrrancqWZu5r
GVSTLef8x7oByOYs4c8OKoF9xTbC5egptrKur8chDpCLcBXCZni/QqwIdvK6opaZaBn+oaoADO+H
/5FA9NI9zHTG1N6+eYU0pnw58TRYm63MyTnde9TCMXAFhJnmjuytQi77CelKM5xeq34oPCi8vY3z
dQvEE1iHE1AtOcJ3YRy6UHmNnsL2QYk+CWolopeK9RkAm9i8O5wwTTAxMA0GCWCGSAFlAwQCAQUA
BCATGNTuJp+iP/TMoDK6Fhb+LZYiioTy5dtQcJjSEsDR5wQUy0GhpfZNW/ycuLzVeuJXaKtHA3YC
AicQ

===== FILE: tools/patch_android.py =====
import pathlib
import re
import sys


def fail(msg):
    print("PATCH ERROR: " + msg)
    sys.exit(1)


root = pathlib.Path("android")

s = root / "settings.gradle"
if not s.exists():
    fail("android/settings.gradle not found (Flutter version changed?)")
t = s.read_text()
t, n = re.subn(
    r'(id "org\.jetbrains\.kotlin\.android" version ")[^"]+(" apply false)',
    r'\g<1>1.9.24\g<2>\n    id "com.google.gms.google-services" version "4.4.2" apply false',
    t, count=1)
if n != 1:
    fail("Kotlin plugin line not found in settings.gradle")
s.write_text(t)

a = root / "app" / "build.gradle"
if not a.exists():
    fail("android/app/build.gradle not found")
t = a.read_text()
t, n = re.subn(
    r'(\n\s*id "org\.jetbrains\.kotlin\.android"[ \t]*\n)',
    r'\1    id "com.google.gms.google-services"\n', t, count=1)
if n != 1:
    fail("Kotlin plugin line not found in app/build.gradle")
t, n = re.subn(r'compileSdk(Version)?\s*=?\s*flutter\.compileSdkVersion', 'compileSdk = 35', t)
if n < 1:
    fail("compileSdk line not found")
t, n = re.subn(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdk = 23', t)
if n < 1:
    fail("minSdk line not found")
a.write_text(t)

g = root / "gradle.properties"
g.write_text(g.read_text().rstrip() + "\nandroid.suppressUnsupportedCompileSdk=35\n")

print("Android project patched OK")

===== FILE: tools/make_icons.py =====
import os
import sys
from PIL import Image, ImageDraw

res = sys.argv[1]
COLORS = [(229, 57, 53), (67, 160, 71), (30, 136, 229), (253, 216, 53)]


def draw_logo(size, with_bg):
    s = 1024
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if with_bg:
        for y in range(s):
            r = int(43 + (91 - 43) * y / s)
            g = int(26 + (43 - 26) * y / s)
            b = int(110 + (181 - 110) * y / s)
            d.line([(0, y), (s, y)], fill=(r, g, b, 255))
    m, gap = 190, 24
    half = (s - 2 * m - gap) // 2
    pos = [(m, m), (m + half + gap, m), (m, m + half + gap), (m + half + gap, m + half + gap)]
    for (x, y), c in zip(pos, COLORS):
        d.rounded_rectangle([x, y, x + half, y + half], radius=80, fill=c + (255,),
                            outline=(255, 255, 255, 255), width=10)
    cx = cy = s // 2
    d.rounded_rectangle([cx - 150, cy - 150, cx + 150, cy + 150], radius=60,
                        fill=(255, 255, 255, 255), outline=(40, 40, 60, 255), width=8)
    for dx, dy in [(-80, -80), (80, -80), (0, 0), (-80, 80), (80, 80)]:
        d.ellipse([cx + dx - 28, cy + dy - 28, cx + dx + 28, cy + dy + 28], fill=(40, 40, 60, 255))
    return im.resize((size, size), Image.LANCZOS)


for folder, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
    p = os.path.join(res, "mipmap-" + folder)
    os.makedirs(p, exist_ok=True)
    draw_logo(px, True).save(os.path.join(p, "ic_launcher.png"))

dp = os.path.join(res, "drawable")
os.makedirs(dp, exist_ok=True)
draw_logo(320, False).save(os.path.join(dp, "splash_logo.png"))
print("Icons generated")

===== FILE: functions/package.json =====
{
  "name": "functions",
  "private": true,
  "main": "index.js",
  "engines": { "node": "20" },
  "dependencies": {
    "firebase-admin": "^12.7.0",
    "firebase-functions": "^6.1.0"
  }
}

===== FILE: functions/index.js =====
'use strict';
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const crypto = require('crypto');

admin.initializeApp();
const db = admin.database();
const OPTS = { region: 'us-central1', maxInstances: 20, memory: '256MiB' };

// ---------- Rules constants ----------
const START = [0, 13, 26, 39];
const SAFE = new Set([0, 8, 13, 21, 26, 34, 39, 47]);
const FINISH = 56;
const TURN_MS = 45000;
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

// ---------- Helpers ----------
function authUid(req) {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
  return req.auth.uid;
}
function cleanCode(v) {
  const c = String(v || '').trim().toUpperCase();
  if (!/^[A-Z0-9]{6}$/.test(c)) throw new HttpsError('invalid-argument', 'Room code must be 6 letters or digits.');
  return c;
}
function newCode() {
  let s = '';
  for (let i = 0; i < 6; i++) s += CODE_CHARS[crypto.randomInt(CODE_CHARS.length)];
  return s;
}
async function getProfile(uid) {
  const v = (await db.ref('users/' + uid).get()).val() || {};
  const name = String(v.name || 'Player').trim().slice(0, 16) || 'Player';
  const avatar = Number.isInteger(v.avatar) ? v.avatar : 0;
  return { name, avatar };
}
function playerObj(prof, now) {
  return { name: prof.name, avatar: prof.avatar, joinedAt: now, connected: true, lastSeen: now };
}
const absIdx = (color, p) => (START[color] + p) % 52;

async function mutate(code, fn) {
  const ref = db.ref('rooms/' + code);
  let existed = false, err = null, out = null;
  await ref.transaction((room) => {
    existed = false; err = null; out = null;
    if (room === null) return null;
    existed = true;
    const ctx = { remove: false };
    try { out = fn(room, Date.now(), ctx); } catch (e) { err = e; return; }
    return ctx.remove ? null : room;
  });
  if (!existed) throw new HttpsError('not-found', 'Room not found.');
  if (err) throw err;
  return out;
}

function needPlaying(room) {
  if (room.status !== 'playing' || !room.game) throw new HttpsError('failed-precondition', 'The game is not running.');
  return room.game;
}
function uidByColor(room, color) {
  for (const [u, p] of Object.entries(room.players || {})) if (p.color === color) return u;
  return null;
}
function activeColors(room) {
  return room.game.order.filter((c) => {
    const u = uidByColor(room, c);
    return u && !room.players[u].left;
  });
}
function passTurn(room, now) {
  const g = room.game;
  const act = activeColors(room);
  if (act.length === 0) return;
  const i = g.order.indexOf(g.turn);
  for (let k = 1; k <= g.order.length; k++) {
    const c = g.order[(i + k) % g.order.length];
    if (act.includes(c)) { g.turn = c; break; }
  }
  g.phase = 'roll';
  delete g.movable;
  g.sixes = 0;
  g.turnDeadline = now + TURN_MS;
  g.seq = (g.seq || 0) + 1;
}
function finishGame(room, winnerColor, now) {
  const g = room.game;
  room.status = 'finished';
  room.finishedAt = now;
  g.phase = 'over';
  delete g.movable;
  if (winnerColor !== null && winnerColor !== undefined) g.winner = winnerColor;
  g.seq = (g.seq || 0) + 1;
  const uids = Object.entries(room.players).filter(([, p]) => p.color !== undefined).map(([u]) => u);
  return { uids, winner: winnerColor === null || winnerColor === undefined ? null : uidByColor(room, winnerColor) };
}
function movableTokens(tokens, dice) {
  const r = [];
  tokens.forEach((p, i) => {
    if (p === -1) { if (dice === 6) r.push(i); }
    else if (p < FINISH && p + dice <= FINISH) r.push(i);
  });
  return r;
}
function beginGame(room, now) {
  const entries = Object.entries(room.players).sort((a, b) => a[1].joinedAt - b[1].joinedAt);
  const n = entries.length;
  const seats = n === 2 ? [0, 2] : n === 3 ? [0, 1, 2] : [0, 1, 2, 3];
  const tokens = {};
  entries.forEach(([, p], i) => { p.color = seats[i]; p.missed = 0; tokens['c' + seats[i]] = [-1, -1, -1, -1]; });
  room.status = 'playing';
  room.startedAt = now;
  delete room.isPublic;
  room.game = { order: seats, tokens, turn: seats[0], phase: 'roll', dice: 0, diceSeq: 0, seq: 0, sixes: 0, turnDeadline: now + TURN_MS };
}
function joinLogic(room, uid, prof, now) {
  const ex = room.players[uid];
  if (ex) {
    if (ex.left) throw new HttpsError('failed-precondition', 'You left this game and cannot rejoin it.');
    return;
  }
  if (room.status !== 'lobby') throw new HttpsError('failed-precondition', 'This game has already started.');
  if (Object.keys(room.players).length >= room.maxPlayers) throw new HttpsError('resource-exhausted', 'This room is full.');
  room.players[uid] = playerObj(prof, now);
  if (room.isPublic && Object.keys(room.players).length === room.maxPlayers) beginGame(room, now);
}
async function recordStats(stats) {
  try {
    for (const u of stats.uids) {
      await db.ref('stats/' + u + '/gamesPlayed').transaction((v) => (v || 0) + 1);
    }
    if (stats.winner) await db.ref('stats/' + stats.winner + '/wins').transaction((v) => (v || 0) + 1);
  } catch (e) { console.error('stats error', e); }
}
async function finalize(out) {
  if (out && out.stats) { await recordStats(out.stats); delete out.stats; }
  return out || { ok: true };
}
async function cleanupOld(now) {
  try {
    const old = await db.ref('rooms').orderByChild('createdAt').endAt(now - 24 * 3600 * 1000).limitToFirst(25).get();
    const updates = {};
    old.forEach((s) => { updates[s.key] = null; });
    if (Object.keys(updates).length) await db.ref('rooms').update(updates);
  } catch (e) { console.error('cleanup error', e); }
}
async function makeRoom(uid, prof, max, isPublic) {
  const now = Date.now();
  await cleanupOld(now);
  for (let t = 0; t < 10; t++) {
    const code = newCode();
    const room = { code, host: uid, status: 'lobby', createdAt: now, maxPlayers: max, players: {} };
    if (isPublic) room.isPublic = true;
    room.players[uid] = playerObj(prof, now);
    const res = await db.ref('rooms/' + code).transaction((cur) => (cur === null ? room : undefined));
    if (res.committed) return { code, status: 'lobby' };
  }
  throw new HttpsError('internal', 'Could not create a room. Please try again.');
}

// ---------- Callable functions ----------
exports.createRoom = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const prof = await getProfile(uid);
  const max = Math.min(4, Math.max(2, parseInt(req.data && req.data.maxPlayers, 10) || 4));
  return makeRoom(uid, prof, max, false);
});

exports.joinRoom = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const code = cleanCode(req.data && req.data.code);
  const prof = await getProfile(uid);
  return mutate(code, (room, now) => {
    joinLogic(room, uid, prof, now);
    return { code, status: room.status };
  });
});

exports.quickMatch = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const prof = await getProfile(uid);
  const now = Date.now();
  const snap = await db.ref('rooms').orderByChild('isPublic').equalTo(true).limitToLast(40).get();
  const cands = [];
  snap.forEach((s) => {
    const r = s.val();
    if (r && r.status === 'lobby' && now - r.createdAt < 15 * 60000 && r.players &&
        (r.players[uid] || Object.keys(r.players).length < r.maxPlayers)) cands.push(s.key);
  });
  for (const code of cands) {
    try {
      return await mutate(code, (room, n) => { joinLogic(room, uid, prof, n); return { code, status: room.status }; });
    } catch (e) { /* room filled or vanished, try next */ }
  }
  return makeRoom(uid, prof, 4, true);
});

exports.startGame = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const code = cleanCode(req.data && req.data.code);
  return mutate(code, (room, now) => {
    if (room.host !== uid) throw new HttpsError('permission-denied', 'Only the host can start the game.');
    if (room.status !== 'lobby') throw new HttpsError('failed-precondition', 'The game has already started.');
    if (Object.keys(room.players).length < 2) throw new HttpsError('failed-precondition', 'At least 2 players are needed.');
    beginGame(room, now);
    return { ok: true };
  });
});

exports.rollDice = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const code = cleanCode(req.data && req.data.code);
  const out = await mutate(code, (room, now) => {
    const g = needPlaying(room);
    const me = room.players[uid];
    if (!me || me.left || g.turn !== me.color) throw new HttpsError('failed-precondition', 'It is not your turn.');
    if (g.phase !== 'roll') throw new HttpsError('failed-precondition', 'Move a token first.');
    const dice = crypto.randomInt(1, 7);
    me.missed = 0;
    g.dice = dice;
    g.diceSeq = (g.diceSeq || 0) + 1;
    g.rolledBy = me.color;
    g.seq = (g.seq || 0) + 1;
    delete g.event;
    g.sixes = dice === 6 ? (g.sixes || 0) + 1 : 0;
    if (g.sixes >= 3) {
      g.event = me.name + ' rolled three sixes in a row - turn lost!';
      passTurn(room, now);
      return { dice };
    }
    const mv = movableTokens(g.tokens['c' + me.color], dice);
    if (mv.length === 0) {
      g.event = me.name + ' rolled ' + dice + ' - no move possible';
      passTurn(room, now);
      return { dice };
    }
    g.phase = 'move';
    g.movable = mv;
    g.turnDeadline = now + TURN_MS;
    return { dice };
  });
  return finalize(out);
});

exports.moveToken = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const code = cleanCode(req.data && req.data.code);
  const idx = parseInt(req.data && req.data.token, 10);
  const out = await mutate(code, (room, now) => {
    const g = needPlaying(room);
    const me = room.players[uid];
    if (!me || me.left || g.turn !== me.color) throw new HttpsError('failed-precondition', 'It is not your turn.');
    if (g.phase !== 'move' || !(g.movable || []).includes(idx)) throw new HttpsError('failed-precondition', 'That token cannot move.');
    const toks = g.tokens['c' + me.color];
    const from = toks[idx];
    const to = from === -1 ? 0 : from + g.dice;
    toks[idx] = to;
    me.missed = 0;
    let captured = 0;
    if (to <= 50) {
      const a = absIdx(me.color, to);
      if (!SAFE.has(a)) {
        for (const c of g.order) {
          if (c === me.color) continue;
          const arr = g.tokens['c' + c];
          arr.forEach((p, j) => {
            if (p >= 0 && p <= 50 && absIdx(c, p) === a) { arr[j] = -1; captured++; }
          });
        }
      }
    }
    g.lastMove = { color: me.color, token: idx, from, to, captured };
    g.seq = (g.seq || 0) + 1;
    if (toks.every((p) => p === FINISH)) {
      delete g.event;
      return { ok: true, stats: finishGame(room, me.color, now) };
    }
    const bonus = g.dice === 6 || captured > 0 || to === FINISH;
    if (bonus) {
      g.phase = 'roll';
      delete g.movable;
      g.turnDeadline = now + TURN_MS;
      if (captured > 0) g.event = me.name + ' captured ' + captured + ' token' + (captured > 1 ? 's' : '') + '! Roll again.';
      else if (to === FINISH) g.event = me.name + ' got a token home! Roll again.';
      else g.event = me.name + ' rolled a 6 - roll again!';
    } else {
      delete g.event;
      passTurn(room, now);
    }
    return { ok: true };
  });
  return finalize(out);
});

exports.skipTurn = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const code = cleanCode(req.data && req.data.code);
  const out = await mutate(code, (room, now) => {
    const g = needPlaying(room);
    if (!room.players[uid]) throw new HttpsError('permission-denied', 'You are not in this room.');
    const curUid = uidByColor(room, g.turn);
    const cur = curUid && room.players[curUid];
    if (!cur) throw new HttpsError('failed-precondition', 'Nothing to skip.');
    const expired = now > g.turnDeadline;
    const dropped = cur.connected === false && cur.lastSeen && now - cur.lastSeen > 10000;
    if (!expired && !dropped) throw new HttpsError('failed-precondition', 'The turn is still active.');
    let stats = null;
    if (expired && !dropped) {
      cur.missed = (cur.missed || 0) + 1;
      if (cur.missed >= 3) cur.left = true;
    }
    g.event = cur.name + (cur.left ? ' was removed for inactivity' : ' missed a turn');
    const act = activeColors(room);
    if (act.length < 2) stats = finishGame(room, act.length ? act[0] : null, now);
    else passTurn(room, now);
    return { ok: true, stats };
  });
  return finalize(out);
});

exports.leaveRoom = onCall(OPTS, async (req) => {
  const uid = authUid(req);
  const code = cleanCode(req.data && req.data.code);
  let out;
  try {
    out = await mutate(code, (room, now, ctx) => {
      const me = room.players[uid];
      if (!me) return { ok: true };
      if (room.status === 'lobby') {
        delete room.players[uid];
        const rest = Object.entries(room.players);
        if (rest.length === 0) ctx.remove = true;
        else if (room.host === uid) {
          rest.sort((a, b) => a[1].joinedAt - b[1].joinedAt);
          room.host = rest[0][0];
        }
        return { ok: true };
      }
      if (room.status === 'playing') {
        me.left = true;
        me.connected = false;
        const g = room.game;
        const act = activeColors(room);
        if (act.length < 2) return { ok: true, stats: finishGame(room, act.length ? act[0] : null, now) };
        if (g.turn === me.color) passTurn(room, now);
      }
      return { ok: true };
    });
  } catch (e) {
    if (e.code === 'not-found') return { ok: true };
    throw e;
  }
  return finalize(out);
});

===== FILE: hosting/public/.well-known/assetlinks.json =====
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.mahin.ludo",
      "sha256_cert_fingerprints": [
        "35:A3:07:8D:57:33:99:66:DF:D0:DE:E4:55:EF:90:75:DB:DC:BA:3F:C8:0B:7B:8A:E0:E7:49:88:3D:86:B8:66"
      ]
    }
  }
]

===== FILE: hosting/public/index.html =====
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mahin's Ludo</title>
<style>
  body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;font-family:system-ui,sans-serif;color:#fff;background:linear-gradient(135deg,#2b1a6e,#5b2bb5,#1e88e5);text-align:center}
  .card{padding:32px;max-width:380px}
  h1{font-size:34px;margin:8px 0}
  a.btn{display:block;margin:16px 0;padding:16px;border-radius:30px;background:#ff8f00;color:#fff;text-decoration:none;font-weight:800;font-size:18px}
  .dice{font-size:72px}
</style>
</head>
<body>
<div class="card">
  <div class="dice">🎲</div>
  <h1>Mahin's Ludo</h1>
  <p>Play online Ludo with your friends. 2 to 4 players.</p>
  <a class="btn" href="/MahinsLudo.apk">Download for Android</a>
  <p style="opacity:.7;font-size:13px">After installing, open an invite link from a friend or enter the room code.</p>
</div>
</body>
</html>

===== FILE: hosting/public/join.html =====
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Join Mahin's Ludo</title>
<style>
  body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;font-family:system-ui,sans-serif;color:#fff;background:linear-gradient(135deg,#2b1a6e,#5b2bb5,#1e88e5);text-align:center}
  .card{padding:28px;max-width:380px;width:100%}
  .code{font-size:46px;font-weight:900;letter-spacing:8px;background:rgba(255,255,255,.15);border-radius:18px;padding:14px;margin:14px 0}
  a.btn,button.btn{display:block;width:100%;box-sizing:border-box;margin:12px 0;padding:16px;border:0;border-radius:30px;color:#fff;text-decoration:none;font-weight:800;font-size:18px;cursor:pointer}
  .orange{background:#ff8f00}.green{background:#2e7d32}.grey{background:rgba(255,255,255,.2)}
</style>
</head>
<body>
<div class="card">
  <div style="font-size:64px">🎲</div>
  <h2>You're invited to Mahin's Ludo!</h2>
  <div>Room code</div>
  <div class="code" id="code">------</div>
  <a class="btn orange" id="open" href="#">Open in Mahin's Ludo</a>
  <a class="btn green" href="/MahinsLudo.apk">Download the game</a>
  <button class="btn grey" id="copy">Copy room code</button>
  <p style="opacity:.75;font-size:13px">Installed the game already? Open it, tap Join Room and type the code above.</p>
</div>
<script>
  var parts = location.pathname.split('/').filter(Boolean);
  var code = (parts[parts.length - 1] || '').toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 6);
  document.getElementById('code').textContent = code || '------';
  document.getElementById('open').href =
    'intent://join/' + code + '#Intent;scheme=mahinsludo;package=com.mahin.ludo;end';
  document.getElementById('copy').onclick = function () {
    if (navigator.clipboard) navigator.clipboard.writeText(code);
    this.textContent = 'Copied!';
  };
</script>
</body>
</html>

===== FILE: lib/config.dart =====
const String kHostingDomain = String.fromEnvironment('HOSTING_DOMAIN', defaultValue: 'localhost');
const String kDatabaseUrl = String.fromEnvironment('DATABASE_URL');
const String kFunctionsRegion = 'us-central1';

String? bootError;

String inviteLink(String code) => 'https://$kHostingDomain/join/$code';

String inviteMessage(String code) =>
    "🎲 Join my game in Mahin's Ludo!\n"
    'Room code: $code\n'
    'Tap to join: ${inviteLink(code)}\n'
    "(No app yet? The link opens a download page.)";

===== FILE: lib/settings.dart =====
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static final ValueNotifier<bool> sound = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> vibration = ValueNotifier<bool>(true);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    sound.value = p.getBool('sound') ?? true;
    vibration.value = p.getBool('vibration') ?? true;
  }

  static Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('sound', sound.value);
    await p.setBool('vibration', vibration.value);
  }

  static void tap() {
    if (vibration.value) HapticFeedback.lightImpact();
    if (sound.value) SystemSound.play(SystemSoundType.click);
  }
}

===== FILE: lib/deep_links.dart =====
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'screens/menu_screens.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

class DeepLinks {
  static String? pending;
  static bool ready = false;
  static VoidCallback? onReturn;
  static final AppLinks _links = AppLinks();

  static Future<void> init() async {
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {}
    _links.uriLinkStream.listen(_handle, onError: (_) {});
  }

  static String? parse(Uri u) {
    final candidates = <String>[...u.pathSegments, u.host];
    for (final c in candidates) {
      if (RegExp(r'^[A-Za-z0-9]{6}$').hasMatch(c)) return c.toUpperCase();
    }
    return null;
  }

  static void _handle(Uri u) {
    final code = parse(u);
    if (code == null) return;
    if (ready) {
      _open(code);
    } else {
      pending = code;
    }
  }

  static void _open(String code) {
    navKey.currentState
        ?.push(MaterialPageRoute(builder: (_) => JoinRoomScreen(initialCode: code, autoJoin: true)))
        .then((_) => onReturn?.call());
  }

  static void consumePending() {
    ready = true;
    final c = pending;
    pending = null;
    if (c != null) _open(c);
  }
}

===== FILE: lib/main.dart =====
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'backend.dart';
import 'config.dart';
import 'deep_links.dart';
import 'screens/splash_screen.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    bootError = 'Firebase is not configured correctly: $e';
  }
  await AppSettings.load();
  DeepLinks.init();
  runApp(const LudoApp());
}

class LudoApp extends StatefulWidget {
  const LudoApp({super.key});
  @override
  State<LudoApp> createState() => _LudoAppState();
}

class _LudoAppState extends State<LudoApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && bootError == null) {
      try {
        Backend.db.goOnline();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Mahin's Ludo",
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C4DFF),
      ),
      home: const SplashScreen(),
    );
  }
}

===== FILE: lib/models.dart =====
Map<String, dynamic> asMap(Object? v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return <String, dynamic>{};
}

int toInt(Object? v, int d) => v is num ? v.toInt() : d;

List<int> asIntList(Object? v) {
  if (v is List) return v.map((e) => e is num ? e.toInt() : 0).toList();
  if (v is Map) {
    final es = v.entries.toList()
      ..sort((a, b) => int.parse('${a.key}').compareTo(int.parse('${b.key}')));
    return es.map((e) => e.value is num ? (e.value as num).toInt() : 0).toList();
  }
  return <int>[];
}

class RoomPlayer {
  final String uid, name;
  final int avatar, joinedAt, lastSeen;
  final int? color;
  final bool connected, left;
  RoomPlayer({
    required this.uid,
    required this.name,
    required this.avatar,
    required this.joinedAt,
    required this.lastSeen,
    required this.color,
    required this.connected,
    required this.left,
  });
  factory RoomPlayer.from(String uid, Map<String, dynamic> m) => RoomPlayer(
        uid: uid,
        name: (m['name'] ?? 'Player').toString(),
        avatar: toInt(m['avatar'], 0),
        joinedAt: toInt(m['joinedAt'], 0),
        lastSeen: toInt(m['lastSeen'], 0),
        color: m['color'] is num ? (m['color'] as num).toInt() : null,
        connected: m['connected'] != false,
        left: m['left'] == true,
      );
}

class GameState {
  final List<int> order;
  final Map<int, List<int>> tokens;
  final int turn, dice, diceSeq, seq, turnDeadline;
  final String phase, event;
  final List<int> movable;
  final int? winner, rolledBy;
  GameState({
    required this.order,
    required this.tokens,
    required this.turn,
    required this.dice,
    required this.diceSeq,
    required this.seq,
    required this.turnDeadline,
    required this.phase,
    required this.event,
    required this.movable,
    required this.winner,
    required this.rolledBy,
  });
  factory GameState.from(Map<String, dynamic> m) {
    final tk = <int, List<int>>{};
    asMap(m['tokens']).forEach((k, v) {
      tk[int.parse(k.substring(1))] = asIntList(v);
    });
    return GameState(
      order: asIntList(m['order']),
      tokens: tk,
      turn: toInt(m['turn'], 0),
      dice: toInt(m['dice'], 0),
      diceSeq: toInt(m['diceSeq'], 0),
      seq: toInt(m['seq'], 0),
      turnDeadline: toInt(m['turnDeadline'], 0),
      phase: (m['phase'] ?? 'roll').toString(),
      event: (m['event'] ?? '').toString(),
      movable: asIntList(m['movable']),
      winner: m['winner'] is num ? (m['winner'] as num).toInt() : null,
      rolledBy: m['rolledBy'] is num ? (m['rolledBy'] as num).toInt() : null,
    );
  }
}

class Room {
  final String code, host, status;
  final int maxPlayers;
  final Map<String, RoomPlayer> players;
  final GameState? game;
  Room({
    required this.code,
    required this.host,
    required this.status,
    required this.maxPlayers,
    required this.players,
    required this.game,
  });

  factory Room.parse(String code, Object? raw) {
    final m = asMap(raw);
    final players = <String, RoomPlayer>{};
    asMap(m['players']).forEach((k, v) {
      players[k] = RoomPlayer.from(k, asMap(v));
    });
    return Room(
      code: code,
      host: (m['host'] ?? '').toString(),
      status: (m['status'] ?? 'lobby').toString(),
      maxPlayers: toInt(m['maxPlayers'], 4),
      players: players,
      game: m['game'] == null ? null : GameState.from(asMap(m['game'])),
    );
  }

  RoomPlayer? byColor(int c) {
    for (final p in players.values) {
      if (p.color == c) return p;
    }
    return null;
  }

  List<RoomPlayer> get sortedPlayers {
    final l = players.values.toList()..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    return l;
  }
}

===== FILE: lib/backend.dart =====
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'models.dart';

class BackendException implements Exception {
  final String message;
  BackendException(this.message);
  @override
  String toString() => message;
}

class Profile {
  final String name;
  final int avatar;
  Profile(this.name, this.avatar);
}

class Backend {
  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseDatabase get db => kDatabaseUrl.isEmpty
      ? FirebaseDatabase.instance
      : FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: kDatabaseUrl);
  static FirebaseFunctions get fn => FirebaseFunctions.instanceFor(region: kFunctionsRegion);
  static String get uid => auth.currentUser!.uid;

  static int _offset = 0;
  static StreamSubscription? _offsetSub;
  static int now() => DateTime.now().millisecondsSinceEpoch + _offset;

  static Future<void> init() async {
    if (auth.currentUser == null) await auth.signInAnonymously();
    _offsetSub ??= db.ref('.info/serverTimeOffset').onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is num) _offset = v.toInt();
    });
  }

  static Future<Profile?> loadProfile() async {
    final s = await db.ref('users/$uid').get();
    if (!s.exists) return null;
    final m = asMap(s.value);
    final n = m['name'];
    if (n is! String || n.isEmpty) return null;
    return Profile(n, toInt(m['avatar'], 0));
  }

  static Future<void> saveProfile(Profile p) =>
      db.ref('users/$uid').set({'name': p.name, 'avatar': p.avatar});

  static Future<Map<String, int>> loadStats() async {
    final s = await db.ref('stats/$uid').get();
    final m = asMap(s.value);
    return {'gamesPlayed': toInt(m['gamesPlayed'], 0), 'wins': toInt(m['wins'], 0)};
  }

  static Future<void> resetGuest() async {
    detachPresence();
    await forgetRoom();
    await auth.signOut();
  }

  static Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final r = await fn.httpsCallable(name).call(data);
      return asMap(r.data);
    } on FirebaseFunctionsException catch (e) {
      throw BackendException(e.message ?? 'Server error (${e.code})');
    } catch (_) {
      throw BackendException('Connection problem. Check your internet and try again.');
    }
  }

  static Future<Map<String, dynamic>> _remember(Future<Map<String, dynamic>> f) async {
    final r = await f;
    final code = r['code'];
    if (code is String) {
      final p = await SharedPreferences.getInstance();
      await p.setString('lastRoom', code);
    }
    return r;
  }

  static Future<Map<String, dynamic>> createRoom(int maxPlayers) =>
      _remember(_call('createRoom', {'maxPlayers': maxPlayers}));
  static Future<Map<String, dynamic>> joinRoom(String code) =>
      _remember(_call('joinRoom', {'code': code}));
  static Future<Map<String, dynamic>> quickMatch() => _remember(_call('quickMatch', {}));
  static Future<void> startGame(String code) => _call('startGame', {'code': code});
  static Future<void> rollDice(String code) => _call('rollDice', {'code': code});
  static Future<void> moveToken(String code, int token) =>
      _call('moveToken', {'code': code, 'token': token});
  static Future<void> skipTurn(String code) => _call('skipTurn', {'code': code});

  static Future<void> leaveRoom(String code) async {
    try {
      await _call('leaveRoom', {'code': code});
    } finally {
      await forgetRoom();
    }
  }

  static Stream<Room?> watchRoom(String code) => db
      .ref('rooms/$code')
      .onValue
      .map((e) => e.snapshot.exists ? Room.parse(code, e.snapshot.value) : null);

  static Future<void> forgetRoom() async {
    detachPresence();
    final p = await SharedPreferences.getInstance();
    await p.remove('lastRoom');
  }

  static Future<String?> activeRoom() async {
    final p = await SharedPreferences.getInstance();
    final code = p.getString('lastRoom');
    if (code == null) return null;
    try {
      final s = await db.ref('rooms/$code').get();
      if (!s.exists) {
        await p.remove('lastRoom');
        return null;
      }
      final room = Room.parse(code, s.value);
      final me = room.players[uid];
      if (me == null || me.left || room.status == 'finished') {
        await p.remove('lastRoom');
        return null;
      }
      return code;
    } catch (_) {
      return null;
    }
  }

  static StreamSubscription? _presenceSub;
  static String? _presenceCode;

  static void attachPresence(String code) {
    if (_presenceCode == code) return;
    detachPresence();
    _presenceCode = code;
    final me = db.ref('rooms/$code/players/$uid');
    _presenceSub = db.ref('.info/connected').onValue.listen((e) async {
      if (e.snapshot.value == true) {
        try {
          await me.child('connected').onDisconnect().set(false);
          await me.child('lastSeen').onDisconnect().set(ServerValue.timestamp);
          await me.child('connected').set(true);
          await me.child('lastSeen').set(ServerValue.timestamp);
        } catch (_) {}
      }
    });
  }

  static void detachPresence() {
    _presenceSub?.cancel();
    _presenceSub = null;
    _presenceCode = null;
  }
}

===== FILE: lib/ludo_layout.dart =====
import 'package:flutter/material.dart';

const List<String> colorNames = ['Red', 'Green', 'Yellow', 'Blue'];
const List<Color> colorValues = [
  Color(0xFFE53935),
  Color(0xFF43A047),
  Color(0xFFFDD835),
  Color(0xFF1E88E5),
];
const List<int> startOffset = [0, 13, 26, 39];
const Set<int> safeSquares = {0, 8, 13, 21, 26, 34, 39, 47};
const int finishPos = 56;

const List<List<int>> trackCells = [
  [6, 1], [6, 2], [6, 3], [6, 4], [6, 5],
  [5, 6], [4, 6], [3, 6], [2, 6], [1, 6], [0, 6],
  [0, 7], [0, 8],
  [1, 8], [2, 8], [3, 8], [4, 8], [5, 8],
  [6, 9], [6, 10], [6, 11], [6, 12], [6, 13], [6, 14],
  [7, 14], [8, 14],
  [8, 13], [8, 12], [8, 11], [8, 10], [8, 9],
  [9, 8], [10, 8], [11, 8], [12, 8], [13, 8], [14, 8],
  [14, 7], [14, 6],
  [13, 6], [12, 6], [11, 6], [10, 6], [9, 6],
  [8, 5], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0],
  [7, 0], [6, 0],
];

const List<List<List<int>>> homeCells = [
  [[7, 1], [7, 2], [7, 3], [7, 4], [7, 5]],
  [[1, 7], [2, 7], [3, 7], [4, 7], [5, 7]],
  [[7, 13], [7, 12], [7, 11], [7, 10], [7, 9]],
  [[13, 7], [12, 7], [11, 7], [10, 7], [9, 7]],
];

const List<Offset> yardOrigin = [Offset(0, 0), Offset(9, 0), Offset(9, 9), Offset(0, 9)];
const List<Offset> homeCenter = [Offset(6.7, 7.5), Offset(7.5, 6.7), Offset(8.3, 7.5), Offset(7.5, 8.3)];
const List<Offset> _yardSlots = [Offset(2, 2), Offset(4, 2), Offset(2, 4), Offset(4, 4)];

Offset _stepPoint(int color, int k) {
  if (k <= 50) {
    final c = trackCells[(startOffset[color] + k) % 52];
    return Offset(c[1] + 0.5, c[0] + 0.5);
  }
  if (k <= 55) {
    final c = homeCells[color][k - 51];
    return Offset(c[1] + 0.5, c[0] + 0.5);
  }
  return homeCenter[color];
}

Offset tokenPoint(int color, int index, double p) {
  if (p < 0) return yardOrigin[color] + _yardSlots[index];
  final lo = p.floor();
  final hi = p.ceil();
  final a = _stepPoint(color, lo);
  if (lo == hi) return a;
  return Offset.lerp(a, _stepPoint(color, hi), p - lo)!;
}

===== FILE: lib/widgets/common.dart =====
import 'package:flutter/material.dart';
import '../ludo_layout.dart';
import '../settings.dart';

const List<String> kAvatars = ['😎', '🦁', '🐯', '🦊', '🐼', '🐸', '🦄', '🐙', '🚀', '⚡', '🔥', '👑'];

class GradientBg extends StatelessWidget {
  final Widget child;
  const GradientBg({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B1A6E), Color(0xFF5B2BB5), Color(0xFF1E88E5)],
        ),
      ),
      child: child,
    );
  }
}

void showMsg(BuildContext c, String t) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t)));
}

class BigButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final bool busy;
  const BigButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = const Color(0xFFFF8F00),
    this.busy = false,
  });
  @override
  State<BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<BigButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.busy;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: () => setState(() => _down = false),
      onTap: enabled
          ? () {
              AppSettings.tap();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 90),
        child: Opacity(
          opacity: (enabled || widget.busy) ? 1 : 0.5,
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [widget.color, Color.lerp(widget.color, Colors.black, 0.25)!]),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white24, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 5))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                widget.busy
                    ? const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                    : Icon(widget.icon, color: Colors.white, size: 26),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AvatarBubble extends StatelessWidget {
  final int index;
  final double size;
  final Color? ring;
  const AvatarBubble({super.key, required this.index, this.size = 44, this.ring});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: ring ?? Colors.white54, width: 3),
      ),
      child: Text(kAvatars[index % kAvatars.length], style: TextStyle(fontSize: size * 0.55)),
    );
  }
}

class LudoLogo extends StatelessWidget {
  final double size;
  const LudoLogo({super.key, this.size = 120});
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter()));
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final gap = s * 0.04;
    final h = (s - gap * 3) / 2;
    final cols = [colorValues[0], colorValues[1], colorValues[3], colorValues[2]];
    final pos = [Offset(gap, gap), Offset(gap * 2 + h, gap), Offset(gap, gap * 2 + h), Offset(gap * 2 + h, gap * 2 + h)];
    final p = Paint();
    for (var i = 0; i < 4; i++) {
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(pos[i].dx, pos[i].dy, h, h), Radius.circular(s * 0.12));
      canvas.drawRRect(r.shift(Offset(0, s * 0.02)), p..color = Colors.black26);
      canvas.drawRRect(r, p..color = cols[i]);
      canvas.drawRRect(r, Paint()..style = PaintingStyle.stroke..strokeWidth = s * 0.015..color = Colors.white);
    }
    final c = Offset(s / 2, s / 2);
    final die = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: s * 0.42, height: s * 0.42), Radius.circular(s * 0.09));
    canvas.drawRRect(die, p..color = Colors.white);
    final dot = Paint()..color = const Color(0xFF28283C);
    for (final d in const [Offset(-1, -1), Offset(1, -1), Offset(0, 0), Offset(-1, 1), Offset(1, 1)]) {
      canvas.drawCircle(c + d * (s * 0.1), s * 0.035, dot);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

===== FILE: lib/widgets/board_painter.dart =====
import 'dart:math';
import 'package:flutter/material.dart';
import '../ludo_layout.dart';

class TokenDraw {
  final int color, index;
  final Offset pos;
  final double scale;
  TokenDraw(this.color, this.index, this.pos, this.scale);
}

List<TokenDraw> layoutTokens(Map<int, List<double>> pos, double cell) {
  final groups = <String, List<List<int>>>{};
  final points = <String, Offset>{};
  pos.forEach((c, list) {
    for (var i = 0; i < list.length; i++) {
      final pt = tokenPoint(c, i, list[i]);
      final key = '${(pt.dx * 100).round()}_${(pt.dy * 100).round()}';
      (groups[key] ??= []).add([c, i]);
      points[key] = pt;
    }
  });
  final out = <TokenDraw>[];
  groups.forEach((key, items) {
    final base = points[key]!;
    final n = items.length;
    for (var k = 0; k < n; k++) {
      var off = Offset.zero;
      var sc = 1.0;
      if (n > 1) {
        sc = n == 2 ? 0.8 : 0.7;
        final a = 2 * pi * k / n;
        off = Offset(cos(a), sin(a)) * 0.2;
      }
      out.add(TokenDraw(items[k][0], items[k][1], (base + off) * cell, sc));
    }
  });
  return out;
}

class BoardPainter extends CustomPainter {
  final Map<int, List<double>> from, to;
  final Animation<double> move, pulse;
  final Set<int> highlight;
  final int? highlightColor;

  BoardPainter({
    required this.from,
    required this.to,
    required this.move,
    required this.pulse,
    required this.highlight,
    required this.highlightColor,
  }) : super(repaint: Listenable.merge([move, pulse]));

  static Map<int, List<double>> positions(
      Map<int, List<double>> from, Map<int, List<double>> to, double t) {
    final out = <int, List<double>>{};
    to.forEach((c, list) {
      final f = from[c] ?? list;
      out[c] = List.generate(list.length, (i) {
        final a = i < f.length ? f[i] : list[i];
        final b = list[i];
        if (a == b) return b;
        if (a >= 0 && b > a) return a + (b - a) * Curves.easeInOut.transform(t);
        if (b < 0) return t < 0.85 ? a : b;
        return b;
      });
    });
    return out;
  }

  Path _star(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r * 0.45;
      final a = -pi / 2 + i * pi / 5;
      final pt = c + Offset(cos(a) * rad, sin(a) * rad);
      if (i == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 15;
    final p = Paint();
    final bg = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell * 0.6));
    canvas.save();
    canvas.clipRRect(bg);
    canvas.drawRect(Offset.zero & size, p..color = Colors.white);

    for (var c = 0; c < 4; c++) {
      final o = yardOrigin[c];
      canvas.drawRect(Rect.fromLTWH(o.dx * cell, o.dy * cell, 6 * cell, 6 * cell), p..color = colorValues[c]);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH((o.dx + 1) * cell, (o.dy + 1) * cell, 4 * cell, 4 * cell), Radius.circular(cell * 0.7)),
          p..color = Colors.white);
      for (var i = 0; i < 4; i++) {
        canvas.drawCircle(tokenPoint(c, i, -1) * cell, cell * 0.46, p..color = colorValues[c].withOpacity(0.28));
      }
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFF9E9E9E);
    Rect cellRect(int r, int c) => Rect.fromLTWH(c * cell, r * cell, cell, cell);

    for (var i = 0; i < 52; i++) {
      final t = trackCells[i];
      final r = cellRect(t[0], t[1]);
      var fill = Colors.white;
      var isStart = false;
      for (var c = 0; c < 4; c++) {
        if (startOffset[c] == i) {
          fill = colorValues[c];
          isStart = true;
        }
      }
      canvas.drawRect(r, Paint()..style = PaintingStyle.fill..color = fill);
      canvas.drawRect(r, line);
      if (safeSquares.contains(i)) {
        canvas.drawPath(_star(r.center, cell * 0.34),
            Paint()..color = isStart ? Colors.white70 : const Color(0xFF8D8D8D));
      }
    }

    for (var c = 0; c < 4; c++) {
      for (final h in homeCells[c]) {
        final r = cellRect(h[0], h[1]);
        canvas.drawRect(r, Paint()..color = colorValues[c]);
        canvas.drawRect(r, line);
      }
    }

    Offset g(double x, double y) => Offset(x * cell, y * cell);
    final tri = [
      [g(6, 6), g(6, 9), g(7.5, 7.5)],
      [g(6, 6), g(9, 6), g(7.5, 7.5)],
      [g(9, 6), g(9, 9), g(7.5, 7.5)],
      [g(6, 9), g(9, 9), g(7.5, 7.5)],
    ];
    for (var c = 0; c < 4; c++) {
      final path = Path()
        ..moveTo(tri[c][0].dx, tri[c][0].dy)
        ..lineTo(tri[c][1].dx, tri[c][1].dy)
        ..lineTo(tri[c][2].dx, tri[c][2].dy)
        ..close();
      canvas.drawPath(path, Paint()..color = colorValues[c]);
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white54);
    }
    canvas.restore();
    canvas.drawRRect(bg, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white70);

    final pos = positions(from, to, move.value);
    final draws = layoutTokens(pos, cell);
    for (final d in draws) {
      final r = cell * 0.38 * d.scale;
      var hop = 0.0;
      final fl = from[d.color];
      final tl = to[d.color];
      if (fl != null && tl != null && d.index < fl.length && d.index < tl.length) {
        final a = fl[d.index], b = tl[d.index];
        if (a >= 0 && b > a && move.value < 1) {
          hop = sin(move.value * (b - a) * pi).abs() * cell * 0.3;
        }
      }
      final center = d.pos - Offset(0, hop);
      canvas.drawCircle(d.pos + Offset(0, cell * 0.1), r, Paint()..color = Colors.black38);
      canvas.drawCircle(center, r, Paint()..color = colorValues[d.color]);
      canvas.drawCircle(
          center, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.6..color = Colors.white);
      canvas.drawCircle(center, r * 0.62,
          Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = Colors.black26);
      canvas.drawCircle(center - Offset(r * 0.3, r * 0.3), r * 0.28, Paint()..color = Colors.white38);
      if (highlightColor == d.color && highlight.contains(d.index)) {
        canvas.drawCircle(
            center,
            r * (1.3 + 0.2 * pulse.value),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.2
              ..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) => true;
}

===== FILE: lib/widgets/dice_view.dart =====
import 'dart:math';
import 'package:flutter/material.dart';

class DiceView extends StatefulWidget {
  final int value;
  final bool rolling;
  final bool active;
  final VoidCallback? onTap;
  const DiceView({super.key, required this.value, required this.rolling, required this.active, this.onTap});
  @override
  State<DiceView> createState() => _DiceViewState();
}

class _DiceViewState extends State<DiceView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void initState() {
    super.initState();
    if (widget.rolling) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant DiceView old) {
    super.didUpdateWidget(old);
    if (widget.rolling && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.rolling && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final r = widget.rolling;
          final face = r ? ((_c.value * 10).floor() * 5 + 3) % 6 + 1 : (widget.value == 0 ? 1 : widget.value);
          final angle = r ? sin(_c.value * 4 * pi) * 0.4 : 0.0;
          return Transform.rotate(
            angle: angle,
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: widget.active ? const Color(0xFFFFC107) : Colors.black26, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: widget.active ? const Color(0xFFFFC107).withOpacity(0.8) : Colors.black38,
                    blurRadius: widget.active ? 18 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: CustomPaint(painter: _PipPainter(face)),
            ),
          );
        },
      ),
    );
  }
}

class _PipPainter extends CustomPainter {
  final int face;
  _PipPainter(this.face);

  static const Map<int, List<int>> _pips = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF28283C);
    final s = size.width;
    for (final i in _pips[face]!) {
      final row = i ~/ 3, col = i % 3;
      canvas.drawCircle(Offset(s * (0.25 + 0.25 * col), s * (0.25 + 0.25 * row)), s * 0.08, p);
    }
  }

  @override
  bool shouldRepaint(covariant _PipPainter old) => old.face != face;
}

===== FILE: lib/screens/splash_screen.dart =====
import 'package:flutter/material.dart';
import '../backend.dart';
import '../config.dart';
import '../widgets/common.dart';
import 'menu_screens.dart';
import 'profile_settings.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() => _error = null);
    try {
      if (bootError != null) throw Exception(bootError);
      await Future.wait([Backend.init(), Future.delayed(const Duration(milliseconds: 1800))]);
      final profile = await Backend.loadProfile();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => profile == null ? const ProfileScreen(firstRun: true) : const MainMenuScreen()));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBg(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.3, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.elasticOut,
                  builder: (context, v, child) => Transform.scale(scale: v, child: child),
                  child: const LudoLogo(size: 170),
                ),
                const SizedBox(height: 22),
                const Text("Mahin's Ludo",
                    style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 6),
                const Text('Play with friends, anywhere',
                    style: TextStyle(fontSize: 16, color: Colors.white70)),
                const SizedBox(height: 36),
                if (_error == null)
                  const CircularProgressIndicator(color: Colors.white)
                else ...[
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.amber)),
                  const SizedBox(height: 16),
                  SizedBox(width: 200, child: BigButton(label: 'Retry', icon: Icons.refresh, onTap: _boot)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

===== FILE: lib/screens/menu_screens.dart =====
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../backend.dart';
import '../deep_links.dart';
import '../widgets/common.dart';
import 'game_screen.dart';
import 'lobby_screen.dart';
import 'profile_settings.dart';

void openRoom(BuildContext context, String code, String status, {bool replace = false}) {
  final route = MaterialPageRoute(
      builder: (_) => status == 'playing' ? GameScreen(code: code) : LobbyScreen(code: code));
  if (replace) {
    Navigator.pushReplacement(context, route);
  } else {
    Navigator.push(context, route);
  }
}

Widget _page(BuildContext context, String title, List<Widget> children) {
  return Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(title: Text(title), backgroundColor: Colors.transparent, elevation: 0),
    body: GradientBg(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      ),
    ),
  );
}

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});
  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  String? _resume;

  @override
  void initState() {
    super.initState();
    DeepLinks.onReturn = _refresh;
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => DeepLinks.consumePending());
  }

  Future<void> _refresh() async {
    final c = await Backend.activeRoom();
    if (mounted) setState(() => _resume = c);
  }

  Future<void> _resumeGame() async {
    final code = _resume!;
    try {
      final r = await Backend.joinRoom(code);
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => r['status'] == 'playing' ? GameScreen(code: code) : LobbyScreen(code: code)));
      _refresh();
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
      await Backend.forgetRoom();
      _refresh();
    }
  }

  Future<void> _go(Widget w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LudoLogo(size: 130),
                    const SizedBox(height: 10),
                    const Text("Mahin's Ludo",
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 22),
                    if (_resume != null) ...[
                      BigButton(
                          label: 'Resume game  ($_resume)',
                          icon: Icons.play_circle_fill,
                          color: const Color(0xFF2E7D32),
                          onTap: _resumeGame),
                      const SizedBox(height: 14),
                    ],
                    BigButton(label: 'Online Multiplayer', icon: Icons.public, onTap: () => _go(const OnlineScreen())),
                    const SizedBox(height: 14),
                    BigButton(
                        label: 'Play With Friends',
                        icon: Icons.group,
                        color: const Color(0xFF1E88E5),
                        onTap: () => _go(const FriendsScreen())),
                    const SizedBox(height: 14),
                    BigButton(
                        label: 'Player Profile',
                        icon: Icons.person,
                        color: const Color(0xFF8E24AA),
                        onTap: () => _go(const ProfileScreen())),
                    const SizedBox(height: 14),
                    BigButton(
                        label: 'Settings',
                        icon: Icons.settings,
                        color: const Color(0xFF546E7A),
                        onTap: () => _go(const SettingsScreen())),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});
  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  bool _busy = false;

  Future<void> _quick() async {
    setState(() => _busy = true);
    try {
      final r = await Backend.quickMatch();
      if (!mounted) return;
      openRoom(context, r['code'] as String, r['status'] as String, replace: true);
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _page(context, 'Online Multiplayer', [
      const Text('🌍', style: TextStyle(fontSize: 70)),
      const SizedBox(height: 12),
      const Text(
        'Quick Match puts you in an open room with other online players. '
        'The game starts automatically when 4 players have joined, or the room host can start with 2 or more.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, color: Colors.white70),
      ),
      const SizedBox(height: 26),
      BigButton(label: 'Quick Match', icon: Icons.bolt, busy: _busy, onTap: _quick),
      const SizedBox(height: 14),
      BigButton(
          label: 'Play With Friends',
          icon: Icons.group,
          color: const Color(0xFF1E88E5),
          onTap: () => Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const FriendsScreen()))),
    ]);
  }
}

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return _page(context, 'Play With Friends', [
      const Text('👫', style: TextStyle(fontSize: 70)),
      const SizedBox(height: 12),
      const Text('Create a private room and invite friends on WhatsApp, or join one with a code.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.white70)),
      const SizedBox(height: 26),
      BigButton(
          label: 'Create Room',
          icon: Icons.add_circle,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateRoomScreen()))),
      const SizedBox(height: 14),
      BigButton(
          label: 'Join Room',
          icon: Icons.login,
          color: const Color(0xFF2E7D32),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JoinRoomScreen()))),
    ]);
  }
}

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});
  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  int _max = 4;
  bool _busy = false;

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final r = await Backend.createRoom(_max);
      if (!mounted) return;
      openRoom(context, r['code'] as String, 'lobby', replace: true);
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _page(context, 'Create Room', [
      const Text('How many players?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 14),
      Wrap(
        spacing: 12,
        children: [
          for (final n in [2, 3, 4])
            ChoiceChip(
              label: Text('$n players', style: const TextStyle(fontSize: 16)),
              selected: _max == n,
              onSelected: (_) => setState(() => _max = n),
            ),
        ],
      ),
      const SizedBox(height: 28),
      BigButton(label: 'Create Room', icon: Icons.meeting_room, busy: _busy, onTap: _create),
    ]);
  }
}

class JoinRoomScreen extends StatefulWidget {
  final String? initialCode;
  final bool autoJoin;
  const JoinRoomScreen({super.key, this.initialCode, this.autoJoin = false});
  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  late final TextEditingController _ctl = TextEditingController(text: widget.initialCode ?? '');
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoJoin && (widget.initialCode ?? '').length == 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _join());
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _ctl.text.trim().toUpperCase();
    if (code.length != 6) {
      showMsg(context, 'Enter the 6-character room code.');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await Backend.joinRoom(code);
      if (!mounted) return;
      openRoom(context, code, r['status'] as String, replace: true);
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _page(context, 'Join Room', [
      const Text('Enter the room code', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      TextField(
        controller: _ctl,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
          LengthLimitingTextInputFormatter(6),
        ],
        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 8),
        decoration: InputDecoration(
          hintText: 'K7M2QX',
          filled: true,
          fillColor: Colors.white12,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        ),
        onSubmitted: (_) => _join(),
      ),
      const SizedBox(height: 24),
      BigButton(label: 'Join Room', icon: Icons.login, busy: _busy, color: const Color(0xFF2E7D32), onTap: _join),
    ]);
  }
}

===== FILE: lib/screens/lobby_screen.dart =====
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../backend.dart';
import '../config.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'game_screen.dart';

class LobbyScreen extends StatefulWidget {
  final String code;
  const LobbyScreen({super.key, required this.code});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  StreamSubscription<Room?>? _sub;
  Room? _room;
  bool _starting = false, _navigated = false;

  @override
  void initState() {
    super.initState();
    Backend.attachPresence(widget.code);
    _sub = Backend.watchRoom(widget.code).listen(_onRoom, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _gone(String msg) {
    if (_navigated) return;
    _navigated = true;
    Backend.forgetRoom();
    final m = ScaffoldMessenger.of(context);
    m.showSnackBar(SnackBar(content: Text(msg)));
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _onRoom(Room? r) {
    if (!mounted || _navigated) return;
    if (r == null) return _gone('The room was closed.');
    if (r.players[Backend.uid] == null) return _gone('You are no longer in this room.');
    if (r.status == 'playing') {
      _navigated = true;
      _sub?.cancel();
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => GameScreen(code: widget.code)));
      return;
    }
    setState(() => _room = r);
  }

  Future<void> _share() async {
    try {
      await Share.share(inviteMessage(widget.code), subject: "Join my Mahin's Ludo game");
    } catch (_) {
      if (mounted) showMsg(context, 'Could not open the share menu.');
    }
  }

  Future<void> _whatsapp() async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(inviteMessage(widget.code))}');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) await _share();
    } catch (_) {
      await _share();
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) showMsg(context, 'Room code copied: ${widget.code}');
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: inviteLink(widget.code)));
    if (mounted) showMsg(context, 'Invite link copied');
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await Backend.startGame(widget.code);
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leave room?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok != true) return;
    _navigated = true;
    try {
      await Backend.leaveRoom(widget.code);
    } catch (_) {}
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final isHost = room != null && room.host == Backend.uid;
    final players = room?.sortedPlayers ?? <RoomPlayer>[];
    final max = room?.maxPlayers ?? 4;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Room Lobby'),
          backgroundColor: Colors.transparent,
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _leave),
        ),
        extendBodyBehindAppBar: true,
        body: GradientBg(
          child: SafeArea(
            child: room == null
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          children: [
                            const SizedBox(height: 40),
                            const Text('ROOM CODE', style: TextStyle(color: Colors.white70, letterSpacing: 3)),
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                  color: Colors.white12, borderRadius: BorderRadius.circular(20)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(widget.code,
                                      style: const TextStyle(
                                          fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: 8)),
                                  IconButton(onPressed: _copy, icon: const Icon(Icons.copy), tooltip: 'Copy code'),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                    child: BigButton(
                                        label: 'Invite',
                                        icon: Icons.share,
                                        color: const Color(0xFF1E88E5),
                                        onTap: _share)),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: BigButton(
                                        label: 'WhatsApp',
                                        icon: Icons.chat,
                                        color: const Color(0xFF25D366),
                                        onTap: _whatsapp)),
                              ],
                            ),
                            TextButton.icon(
                                onPressed: _copyLink, icon: const Icon(Icons.link), label: const Text('Copy invite link')),
                            const SizedBox(height: 8),
                            Text('Players ${players.length}/$max',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            for (var i = 0; i < max; i++)
                              i < players.length ? _playerTile(players[i], room.host) : _emptyTile(),
                            const SizedBox(height: 20),
                            if (isHost)
                              BigButton(
                                label: 'Start Game',
                                icon: Icons.play_arrow,
                                busy: _starting,
                                color: const Color(0xFF2E7D32),
                                onTap: players.length >= 2 ? _start : null,
                              )
                            else
                              const Text('Waiting for the host to start the game…',
                                  style: TextStyle(color: Colors.white70, fontSize: 16)),
                            if (isHost && players.length < 2)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text('Invite at least one friend to start.',
                                    style: TextStyle(color: Colors.white70)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _playerTile(RoomPlayer p, String host) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          AvatarBubble(index: p.avatar, size: 44),
          const SizedBox(width: 12),
          Expanded(
              child: Text(p.name + (p.uid == Backend.uid ? ' (You)' : ''),
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          if (p.uid == host) const Text('👑 HOST  ', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w800)),
          Icon(Icons.circle, size: 12, color: p.connected ? Colors.greenAccent : Colors.grey),
        ],
      ),
    );
  }

  Widget _emptyTile() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(16)),
      child: const Row(children: [
        Icon(Icons.hourglass_empty, color: Colors.white38),
        SizedBox(width: 14),
        Text('Waiting for player…', style: TextStyle(color: Colors.white38, fontSize: 16)),
      ]),
    );
  }
}

===== FILE: lib/screens/game_screen.dart =====
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../backend.dart';
import '../ludo_layout.dart';
import '../models.dart';
import '../settings.dart';
import '../widgets/board_painter.dart';
import '../widgets/common.dart';
import '../widgets/dice_view.dart';

class GameScreen extends StatefulWidget {
  final String code;
  const GameScreen({super.key, required this.code});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _move =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);

  StreamSubscription<Room?>? _sub;
  Timer? _ticker, _settleTimer;
  Room? _room;
  Map<int, List<double>> _from = {}, _to = {};
  int _lastDiceSeq = -1;
  bool _rollPending = false, _settling = false, _busy = false, _overShown = false, _exiting = false;
  int _remaining = 0, _skipSeq = -1;
  DateTime _skipAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Backend.attachPresence(widget.code);
    _sub = Backend.watchRoom(widget.code).listen(_onRoom, onError: (_) {});
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _ticker?.cancel();
    _settleTimer?.cancel();
    _move.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      try {
        Backend.db.goOnline();
      } catch (_) {}
    }
  }

  void _exit(String? message) {
    if (_exiting || !mounted) return;
    _exiting = true;
    Backend.forgetRoom();
    final m = ScaffoldMessenger.of(context);
    if (message != null) m.showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Map<int, List<double>> _dbl(Map<int, List<int>> t) =>
      t.map((k, v) => MapEntry(k, v.map((e) => e.toDouble()).toList()));

  void _onRoom(Room? r) {
    if (!mounted || _exiting) return;
    if (r == null) return _exit('The room was closed.');
    final me = r.players[Backend.uid];
    if (me == null || me.left) return _exit('You are no longer in this game.');
    final g = r.game;
    if (g != null) {
      final nt = _dbl(g.tokens);
      if (_to.isEmpty) {
        _from = nt;
        _to = nt;
      } else if (!_same(_to, nt)) {
        final cur = BoardPainter.positions(_from, _to, _move.value);
        var steps = 1.0;
        nt.forEach((c, list) {
          for (var i = 0; i < list.length; i++) {
            final old = (_to[c] != null && i < _to[c]!.length) ? _to[c]![i] : list[i];
            if (old >= 0 && list[i] > old) steps = max(steps, list[i] - old);
          }
        });
        _from = cur;
        _to = nt;
        _move.duration = Duration(milliseconds: (steps * 170).clamp(400, 1200).toInt());
        _move.forward(from: 0);
        AppSettings.tap();
      }
      if (g.diceSeq != _lastDiceSeq) {
        if (_lastDiceSeq != -1) {
          _settling = true;
          _settleTimer?.cancel();
          _settleTimer = Timer(const Duration(milliseconds: 650), () {
            if (mounted) setState(() => _settling = false);
          });
        }
        _lastDiceSeq = g.diceSeq;
        _rollPending = false;
      }
    }
    _busy = false;
    setState(() => _room = r);
    if (r.status == 'finished' && !_overShown) {
      _overShown = true;
      Future.delayed(const Duration(milliseconds: 1400), _showWinner);
    }
  }

  bool _same(Map<int, List<double>> a, Map<int, List<double>> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      final x = a[k], y = b[k];
      if (y == null || x!.length != y.length) return false;
      for (var i = 0; i < x.length; i++) {
        if (x[i] != y[i]) return false;
      }
    }
    return true;
  }

  void _tick() {
    final r = _room;
    final g = r?.game;
    if (r == null || g == null || r.status != 'playing' || !mounted) return;
    final left = (g.turnDeadline - Backend.now()) / 1000;
    setState(() => _remaining = max(0, left.ceil()));
    final cur = r.byColor(g.turn);
    if (cur == null) return;
    final expired = Backend.now() > g.turnDeadline + 1500;
    final dropped = !cur.connected && cur.lastSeen > 0 && Backend.now() - cur.lastSeen > 11000;
    if (!(expired || dropped)) return;
    if (_skipSeq == g.seq && DateTime.now().difference(_skipAt).inSeconds < 4) return;
    _skipSeq = g.seq;
    _skipAt = DateTime.now();
    Future.delayed(Duration(milliseconds: Random().nextInt(1200)), () {
      Backend.skipTurn(widget.code).catchError((_) {});
    });
  }

  Future<void> _roll() async {
    final r = _room;
    final g = r?.game;
    final me = r?.players[Backend.uid];
    if (g == null || me == null || g.turn != me.color || g.phase != 'roll' || _rollPending) return;
    setState(() => _rollPending = true);
    AppSettings.tap();
    try {
      await Backend.rollDice(widget.code);
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
    } finally {
      if (mounted) setState(() => _rollPending = false);
    }
  }

  Future<void> _moveToken(int i) async {
    setState(() => _busy = true);
    try {
      await Backend.moveToken(widget.code, i);
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onBoardTap(Offset local, double size) {
    final g = _room?.game;
    final me = _room?.players[Backend.uid];
    if (g == null || me == null || me.color == null) return;
    if (g.turn != me.color || g.phase != 'move' || _busy) return;
    final cell = size / 15;
    int? best;
    var bd = double.infinity;
    for (final d in layoutTokens(_to, cell)) {
      if (d.color != me.color || !g.movable.contains(d.index)) continue;
      final dist = (d.pos - local).distance;
      if (dist < bd) {
        bd = dist;
        best = d.index;
      }
    }
    if (best != null && bd < cell * 0.9) _moveToken(best);
  }

  void _showWinner() {
    final r = _room;
    if (r == null || !mounted || _exiting) return;
    final w = r.game?.winner;
    final p = w == null ? null : r.byColor(w);
    final mine = p != null && p.uid == Backend.uid;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(mine ? '🏆 You won!' : 'Game over'),
        content: Text(p == null
            ? 'The game has ended.'
            : '${p.name} (${colorNames[w!]}) brought all four tokens home!'),
        actions: [
          FilledButton(
              onPressed: () {
                Navigator.pop(c);
                _exit(null);
              },
              child: const Text('Back to menu')),
        ],
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final r = _room;
    if (r == null || r.status == 'finished') return _exit(null);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leave game?'),
        content: const Text('If you leave you cannot rejoin this game. To pause, just close the app instead — you can resume from the menu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await Backend.leaveRoom(widget.code);
      } catch (_) {}
      _exit(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _room;
    final g = r?.game;
    final me = r?.players[Backend.uid];
    final isMyTurn = r != null && g != null && me != null && r.status == 'playing' && g.turn == me.color;
    final canRoll = isMyTurn && g!.phase == 'roll';
    final canMove = isMyTurn && g!.phase == 'move';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        body: GradientBg(
          child: SafeArea(
            child: (r == null || g == null)
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                        child: Row(
                          children: [
                            IconButton(onPressed: _confirmLeave, icon: const Icon(Icons.exit_to_app)),
                            Expanded(
                                child: Text("Mahin's Ludo  •  ${widget.code}",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      _chips(r, g),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: LayoutBuilder(builder: (context, c) {
                            final s = min(c.maxWidth, c.maxHeight);
                            return Center(
                              child: SizedBox(
                                width: s,
                                height: s,
                                child: GestureDetector(
                                  onTapUp: (d) => _onBoardTap(d.localPosition, s),
                                  child: CustomPaint(
                                    painter: BoardPainter(
                                      from: _from,
                                      to: _to,
                                      move: _move,
                                      pulse: _pulse,
                                      highlight: canMove ? g.movable.toSet() : <int>{},
                                      highlightColor: canMove ? me.color : null,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      _bottom(r, g, me, canRoll, canMove),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _chips(Room r, GameState g) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          for (final c in g.order)
            Expanded(
              child: Builder(builder: (context) {
                final p = r.byColor(c);
                final turn = g.turn == c && r.status == 'playing';
                final home = (g.tokens[c] ?? []).where((x) => x == finishPos).length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.all(3),
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: BoxDecoration(
                    color: colorValues[c].withOpacity(turn ? 0.9 : 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: turn ? Colors.white : Colors.white24, width: turn ? 3 : 1),
                    boxShadow: turn ? [BoxShadow(color: colorValues[c], blurRadius: 14)] : null,
                  ),
                  child: Column(
                    children: [
                      AvatarBubble(index: p?.avatar ?? 0, size: 34, ring: colorValues[c]),
                      const SizedBox(height: 2),
                      Text(p?.name ?? '-',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: c == 2 ? Colors.black87 : Colors.white)),
                      Text(
                          p == null
                              ? ''
                              : p.left
                                  ? 'LEFT'
                                  : (!p.connected ? 'OFFLINE' : 'Home $home/4'),
                          style: TextStyle(fontSize: 11, color: c == 2 ? Colors.black87 : Colors.white70)),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _bottom(Room r, GameState g, RoomPlayer? me, bool canRoll, bool canMove) {
    final cur = r.byColor(g.turn);
    String status;
    if (r.status == 'finished') {
      status = 'Game over';
    } else if (canRoll) {
      status = 'Your turn — tap the dice!';
    } else if (canMove) {
      status = 'Tap a glowing token to move';
    } else {
      status = "${cur?.name ?? '…'}'s turn (${colorNames[g.turn]})${cur != null && !cur.connected ? ' - disconnected' : ''}";
    }
    final roller = g.rolledBy == null ? null : r.byColor(g.rolledBy!);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          DiceView(
            value: g.dice,
            rolling: _rollPending || _settling,
            active: canRoll,
            onTap: canRoll ? _roll : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                if (g.dice > 0 && roller != null)
                  Text('${roller.name} rolled ${g.dice}', style: const TextStyle(color: Colors.white70)),
                if (g.event.isNotEmpty)
                  Text(g.event, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w700)),
                if (r.status == 'playing')
                  Text('⏱ ${_remaining}s', style: const TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

===== FILE: lib/screens/profile_settings.dart =====
import 'package:flutter/material.dart';
import '../backend.dart';
import '../settings.dart';
import '../widgets/common.dart';
import 'menu_screens.dart';
import 'splash_screen.dart';

class ProfileScreen extends StatefulWidget {
  final bool firstRun;
  const ProfileScreen({super.key, this.firstRun = false});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _name = TextEditingController();
  int _avatar = 0;
  int _games = 0, _wins = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await Backend.loadProfile();
      final s = await Backend.loadStats();
      if (!mounted) return;
      setState(() {
        if (p != null) {
          _name.text = p.name;
          _avatar = p.avatar;
        }
        _games = s['gamesPlayed'] ?? 0;
        _wins = s['wins'] ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    final n = _name.text.trim();
    if (n.length < 2 || n.length > 16) {
      showMsg(context, 'Name must be 2 to 16 characters.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Backend.saveProfile(Profile(n, _avatar));
      if (!mounted) return;
      if (widget.firstRun) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainMenuScreen()));
      } else {
        showMsg(context, 'Profile saved');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showMsg(context, 'Could not save profile. Check your internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.firstRun ? 'Welcome!' : 'Player Profile'),
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: !widget.firstRun,
      ),
      body: GradientBg(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    AvatarBubble(index: _avatar, size: 96),
                    const SizedBox(height: 6),
                    const Text('Playing as a guest', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _name,
                      maxLength: 16,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        hintText: 'Your name',
                        filled: true,
                        fillColor: Colors.white12,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        for (var i = 0; i < kAvatars.length; i++)
                          GestureDetector(
                            onTap: () => setState(() => _avatar = i),
                            child: AvatarBubble(
                                index: i, size: 52, ring: i == _avatar ? const Color(0xFFFFC107) : Colors.white24),
                          ),
                      ],
                    ),
                    if (!widget.firstRun) ...[
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _stat('Games', _games),
                          _stat('Wins', _wins),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    BigButton(
                        label: widget.firstRun ? 'Continue' : 'Save',
                        icon: Icons.check,
                        busy: _busy,
                        onTap: _save),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, int v) => Column(children: [
        Text('$v', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ]);
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _resetGuest() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New guest account?'),
        content: const Text('You will get a brand-new guest identity. Your name, avatar and stats on this account will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true) return;
    await Backend.resetGuest();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashScreen()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('Settings'), backgroundColor: Colors.transparent),
      body: GradientBg(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: AppSettings.sound,
                    builder: (context, v, _) => SwitchListTile(
                      title: const Text('Sound effects'),
                      secondary: const Icon(Icons.volume_up),
                      value: v,
                      onChanged: (x) {
                        AppSettings.sound.value = x;
                        AppSettings.save();
                      },
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: AppSettings.vibration,
                    builder: (context, v, _) => SwitchListTile(
                      title: const Text('Vibration'),
                      secondary: const Icon(Icons.vibration),
                      value: v,
                      onChanged: (x) {
                        AppSettings.vibration.value = x;
                        AppSettings.save();
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.person_off),
                    title: const Text('Switch to a new guest account'),
                    onTap: _resetGuest,
                  ),
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text("Mahin's Ludo"),
                    subtitle: Text('Version 1.0.0'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
