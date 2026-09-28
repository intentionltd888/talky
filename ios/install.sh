#!/bin/bash
# Talky iPhone 版 — 編譯、簽名、裝到接在這台 Mac 上的 iPhone
#
# 第一次要先做（這三件只有本人能做）：
#   1. iPhone 用線接上 Mac → 解鎖 → 按「信任這部電腦」
#   2. Xcode → Settings → Accounts → ＋ 登入 Apple ID（開發者帳號 CP6J9DCLQL）
#   3. iPhone：設定 → 隱私權與安全性 → 開發者模式 → 打開（會重開機）
# 之後每次改完程式：bash ios/install.sh
# 測試用：bash ios/install.sh --debug（Debug 版，含 scripts/device-test.sh 用的測試入口）
#
# 簽名走 Xcode 自動管理（-allowProvisioningUpdates＋-allowProvisioningDeviceRegistration）：App ID、App Group、描述檔、登記這支手機都自動做。
# 全程不刪檔；產物在 ios/.build/（不進 git）。
set -euo pipefail
cd "$(dirname "$0")"

LOG=.build/install.log
mkdir -p .build
CONFIG=Release
[ "${1:-}" = "--debug" ] && CONFIG=Debug

echo "── 1/4 找 iPhone ──"
JSON=$(mktemp)
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true
DEV=$(python3 - "$JSON" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for dev in d.get("result", {}).get("devices", []):
    hp = dev.get("hardwareProperties", {})
    # 真機的 reality 可能是 "physical" 也可能整欄沒有（iPhone 16 Pro Max／iOS 26.7 實測沒有）；只排除模擬器
    if hp.get("platform") == "iOS" and hp.get("deviceType") == "iPhone" and hp.get("reality") != "simulated":
        name = dev.get("deviceProperties", {}).get("name", "iPhone")
        os_ = dev.get("deviceProperties", {}).get("osVersionNumber", "?")
        print(f'{hp.get("udid", "")}\t{name}\t{os_}')
        break
PY
)
if [ -z "$DEV" ]; then
  echo "✗ 沒看到 iPhone。用線接上、解鎖、按「信任這部電腦」，再跑一次。"
  exit 1
fi
UDID=$(printf '%s' "$DEV" | cut -f1)
NAME=$(printf '%s' "$DEV" | cut -f2)
OSV=$(printf '%s' "$DEV" | cut -f3)
echo "   $NAME（iOS $OSV）"
case "$OSV" in
  1[0-9].* | 2[0-5].*) echo "✗ 要 iOS 26 以上（Apple 內建語音辨識與整理模型從 26 開始）"; exit 1 ;;
esac
if xcrun devicectl device info details --device "$UDID" 2>&1 | grep -q "Developer Mode is turned off"; then
  echo "✗ iPhone 的開發者模式還沒開：設定 → 隱私權與安全性 → 開發者模式 → 打開 → 重新啟動 → 開機後按「打開」"
  exit 1
fi

echo "── 2/4 編譯＋簽名 $CONFIG（第一次約 1–3 分鐘；Xcode 可能要先「準備這支手機」）──"
# 自架的整理服務（選用）：位址放倉外的 ~/.config/talky/ios-bridge-url（一行），編譯時帶進 Info.plist；沒有這個檔就不走這一步
BRIDGE_URL=$(tr -d '[:space:]' < "$HOME/.config/talky/ios-bridge-url" 2>/dev/null || true)
if ! xcodebuild -project Talky.xcodeproj -scheme Talky -configuration "$CONFIG" \
  -destination "id=$UDID" -derivedDataPath .build -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  TALKY_BRIDGE_URL="$BRIDGE_URL" build >"$LOG" 2>&1; then
  echo "✗ 編譯或簽名失敗。最後幾行："
  grep -E "error:|Signing|provision|Developer Mode|account" "$LOG" | tail -8 || tail -15 "$LOG"
  if grep -q -i -E "No Account|No accounts|not signed in|Accounts" "$LOG"; then
    echo "→ Xcode 還沒登入：Xcode → Settings → Accounts → ＋ 登入 Apple ID，再跑一次。"
  fi
  if grep -q -i "Developer Mode" "$LOG"; then
    echo "→ iPhone 要開開發者模式：設定 → 隱私權與安全性 → 開發者模式。"
  fi
  echo "   完整記錄：ios/$LOG"
  exit 1
fi
APP=".build/Build/Products/$CONFIG-iphoneos/Talky.app"
echo "   ✓ $(du -sh "$APP" | cut -f1)"

echo "── 3/4 安裝到 $NAME ──"
xcrun devicectl device install app --device "$UDID" "$APP" >>"$LOG" 2>&1 || {
  echo "✗ 安裝失敗（手機要解鎖）。記錄：ios/$LOG"
  tail -5 "$LOG"
  exit 1
}
echo "   ✓ 裝好了"

echo "── 4/4 打開 Talky ──"
xcrun devicectl device process launch --device "$UDID" ltd.intention.talky.ios >>"$LOG" 2>&1 \
  && echo "   ✓ 已在手機上打開" \
  || echo "   手機鎖著打不開：解鎖後自己點 Talky 圖示"

cat <<'EOF'

接下來在手機上（約 1 分鐘）：
  1. Talky 首頁「設定鍵盤」三步：允許麥克風 → 加入 Talky 鍵盤 → 允許完整取用
  2. 打開任何 App 的輸入框（例如備忘錄），長按 🌐 切到 Talky
  3. 按中間圓鈕 → 第一次會跳到 Talky 開麥克風 → 點左上角「◀」回去 → 直接講 → 按 ■
EOF
