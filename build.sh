#!/usr/bin/env bash
# Build APK trên máy có Flutter + Android SDK.
set -euo pipefail
cd "$(dirname "$0")"

flutter create . --org com.vinh --project-name lumi_reader --platforms android
rm -rf test
python3 tools/patch_android.py .
flutter pub get
flutter build apk --release --split-per-abi

echo
echo "APK nằm ở: build/app/outputs/flutter-apk/"
echo "Máy Android đời mới thường dùng app-arm64-v8a-release.apk"
