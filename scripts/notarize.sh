#!/bin/bash
# notarize.sh — Apple 公證＋釘票：make-dmg.sh 產出 DMG 後跑
#
# 前提：①app 是 Developer ID 簽名（build.sh 自動偵測）②notarytool 憑據已存鑰匙圈
#      （xcrun notarytool store-credentials <profile> --apple-id … --team-id … --password <app 專用密碼>）
# 用法：bash scripts/notarize.sh
# profile 名怎麼找（依序）：TALKY_NOTARY_PROFILE 環境變數 → 倉根 .notary-profile 檔（不進 git，一台機器寫一次）→ 預設 talky-notary
#      Apple 端通常 2–15 分鐘，--wait 會等完。
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="${TALKY_BUILD_DIR:-build}"

APP="$BUILD/Talky.app"
PROFILE="${TALKY_NOTARY_PROFILE:-}"
[ -z "$PROFILE" ] && [ -f .notary-profile ] && PROFILE=$(tr -d '[:space:]' < .notary-profile)
PROFILE="${PROFILE:-talky-notary}"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$BUILD/Talky-$VER.dmg"
[ -f "$DMG" ] || { echo "找不到 $DMG——先跑 bash scripts/make-dmg.sh"; exit 1; }

# 不可用「codesign | grep -q」：pipefail 下 grep -q 提早關管會讓 codesign 吃 SIGPIPE 誤判失敗
SIGN_INFO=$(codesign -dvv "$APP" 2>&1)
echo "$SIGN_INFO" | grep -q "Developer ID Application" \
  || { echo "app 不是 Developer ID 簽名——確認憑證已裝（security find-identity -v -p codesigning）後重跑 build.sh"; exit 1; }

# 出貨閘：DMG 裡的 app 必須就是現在這顆 $BUILD/Talky.app（cdhash 逐位核對；防公證到舊包）
echo "── 出貨閘：DMG 內容＝當下 app ──"
APP_CD=$(codesign -dvvv "$APP" 2>&1 | awk -F= '/^CDHash=/ && !p {print $2; p=1}')
MNT=$(mktemp -d)
hdiutil attach -readonly -nobrowse -mountpoint "$MNT" "$DMG" >/dev/null
DMG_CD=$(codesign -dvvv "$MNT/Talky.app" 2>&1 | awk -F= '/^CDHash=/ && !p {print $2; p=1}')
hdiutil detach "$MNT" >/dev/null
if [ -z "$APP_CD" ] || [ "$APP_CD" != "$DMG_CD" ]; then
  echo "✗ 擋下：DMG 內的 app（${DMG_CD:-?}）≠ 現在的 $BUILD/Talky.app（${APP_CD:-?}）——重跑 make-dmg.sh"
  exit 1
fi
echo "   ✓ 同一顆（cdhash $APP_CD）"

echo "── 提交公證（profile：$PROFILE；--wait 會等 Apple 審完）──"
# notarytool 憑據存在鑰匙圈：登入鑰匙圈被換新時用 TALKY_SIGN_KEYCHAIN 指到舊的那顆（同 build.sh）
NKC="${TALKY_SIGN_KEYCHAIN:-}"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" ${NKC:+--keychain "$NKC"} --wait

echo "── 釘票 ──"
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP" || echo "⚠ 散裝 app 釘票失敗（DMG 已釘票、出貨不受影響）"

echo "── Gatekeeper 驗證 ──"
spctl -a -vv "$APP" && echo "✓ spctl 通過"
cp -f "$DMG" "$BUILD/Talky.dmg"
echo "✅ 公證完成：$DMG（對方拖進 Applications、雙擊打開，零警告）"
