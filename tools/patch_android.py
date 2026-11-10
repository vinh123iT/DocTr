#!/usr/bin/env python3
"""Vá thư mục android/ do `flutter create` sinh ra để chạy được app Lumi Reader.

- Quyền: INTERNET, WAKE_LOCK, FOREGROUND_SERVICE, POST_NOTIFICATIONS
- Dịch vụ nền cho just_audio_background (nghe khi tắt màn hình)
- MainActivity kế thừa AudioServiceActivity
- minSdk 24, tên hiển thị "Lumi Reader"
"""
import glob
import re
import sys
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
android = root / "android"
if not android.exists():
    sys.exit("Không thấy thư mục android/. Hãy chạy `flutter create` trước.")

# ---------- AndroidManifest ----------
manifest = android / "app/src/main/AndroidManifest.xml"
m = manifest.read_text(encoding="utf-8")

perms = [
    "android.permission.INTERNET",
    "android.permission.WAKE_LOCK",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
    "android.permission.POST_NOTIFICATIONS",
]
perm_xml = "".join(
    f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in m
)
if perm_xml:
    m = m.replace("<application", perm_xml + "    <application", 1)

if "com.ryanheise.audioservice.AudioService" not in m:
    services = """
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
"""
    m = m.replace("</application>", services + "    </application>", 1)

m = re.sub(r'android:label="[^"]*"', 'android:label="Lumi Reader"', m, count=1)
manifest.write_text(m, encoding="utf-8")

# ---------- MainActivity ----------
for f in glob.glob(str(android / "app/src/main/**/MainActivity.*"), recursive=True):
    path = Path(f)
    src = path.read_text(encoding="utf-8")
    pkg = re.search(r"^package\s+([\w.]+)", src, re.M)
    if path.suffix == ".kt" and pkg:
        path.write_text(
            f"package {pkg.group(1)}\n\n"
            "import com.ryanheise.audioservice.AudioServiceActivity\n\n"
            "class MainActivity : AudioServiceActivity()\n",
            encoding="utf-8",
        )
        print("Đã vá", path)

# ---------- minSdk ----------
for name in ("build.gradle.kts", "build.gradle"):
    g = android / "app" / name
    if g.exists():
        s = g.read_text(encoding="utf-8")
        s = re.sub(r"minSdk(Version)?\s*=\s*flutter\.minSdkVersion", "minSdk = 24", s)
        s = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", s)
        g.write_text(s, encoding="utf-8")
        print("Đã vá", g)

print("Xong.")
