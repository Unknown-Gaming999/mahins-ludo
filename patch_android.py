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
