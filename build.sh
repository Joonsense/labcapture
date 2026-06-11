#!/bin/bash
# LabCapture 빌드 → .app 번들 생성 → 서명
# 사용법: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "==> swift build (release)"
swift build -c release

APP="dist/LabCapture.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LabCapture "$APP/Contents/MacOS/LabCapture"
cp Support/Info.plist "$APP/Contents/Info.plist"

# 서명: "LabCapture Dev" 자체 서명 인증서가 키체인에 있으면 사용 (재빌드해도 TCC 권한 유지),
# 없으면 ad-hoc (재빌드마다 화면 기록 권한 재허용 필요)
if security find-identity -v -p codesigning 2>/dev/null | grep -q "LabCapture Dev"; then
  codesign --force --sign "LabCapture Dev" "$APP"
  echo "==> 서명: LabCapture Dev (TCC 권한 유지됨)"
else
  codesign --force --sign - "$APP"
  echo "==> 서명: ad-hoc (재빌드 후 화면 기록 권한 재허용 필요)"
fi

echo "==> 완료: $APP"
echo "    실행: open $(pwd)/$APP"
