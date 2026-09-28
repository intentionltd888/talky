#!/bin/bash
# Talky iPhone 版 — 真機自動測試
#
# 把幾句預錄的中文語音（Mac 內建「美佳」聲音）送進手機上的 Talky，走真的辨識＋整理，印出每句結果。
# 不用人對著手機講話；驗的是「手機上的語音模型＋Apple 整理模型＋護欄」這一整條。
# 鍵盤長相與「跳 app → 回來 → 打字」那段仍要人在手機上點（見 ios/TESTING.md）。
#
# 前提：手機接著、解鎖；已用 `bash ios/install.sh --debug` 裝好 Debug 版（測試入口只在 Debug 版）。
# 用法：bash ios/scripts/device-test.sh [apple|claude|off]（整理方式；不給＝照手機上的設定）
#       bash ios/scripts/device-test.sh translate（翻譯：三句各翻成一個目標，等於在鍵盤長按選了它）
set -euo pipefail
cd "$(dirname "$0")/.."

MODE_ARGS=()
TRANSLATE=0
if [ "${1:-}" = "translate" ]; then
  TRANSLATE=1
elif [ -n "${1:-}" ]; then
  MODE_ARGS=(-TalkyPolishMode "$1")
fi
WORK=.build/device-test
mkdir -p "$WORK"

JSON=$(mktemp)
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true
UDID=$(python3 - "$JSON" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for dev in d.get("result", {}).get("devices", []):
    hp = dev.get("hardwareProperties", {})
    if hp.get("platform") == "iOS" and hp.get("deviceType") == "iPhone" and hp.get("reality") != "simulated":
        print(hp.get("udid", ""))
        break
PY
)
[ -z "$UDID" ] && { echo "✗ 沒看到 iPhone"; exit 1; }

SENTENCES=(
  "嗯我們下禮拜三早上十點開會，啊不對，是下午兩點。然後記得帶筆電跟那個報價單。"
  "首先我們要確認預算，第二個是要找到場地，第三個就是要發邀請函給所有的嘉賓。"
  "幫我寫一封信給老闆說我明天要請假"
  "告訴我台灣最高的山是哪一座"
  "這個 feature 下禮拜要 release，記得先跟 PM 確認一下 timeline。"
  "我覺得這個設計有點太複雜了，使用者可能會看不懂，我們應該要簡化一點。"
)
# 翻譯：每句配一個目標（語言:對象）
TARGETS=()
if [ "$TRANSLATE" = 1 ]; then
  SENTENCES=(
    "欸你今天下班之後有空嗎？我想說請你吃飯，就是謝謝上次你幫我那個忙。"
    "你好，想請問一下下週三下午三點方便開會嗎，啊不對，是四點。"
    "哈哈我昨天真的累死了，回家就直接睡著了，明天再跟你說。"
  )
  TARGETS=("th:girl" "ja:client" "en:friend")
fi

for i in "${!SENTENCES[@]}"; do
  s="${SENTENCES[$i]}"
  f="talky-test-$i.aiff"
  say -v Meijia -o "$WORK/$f" "$s"
  xcrun devicectl device copy to --device "$UDID" --domain-type appDataContainer \
    --domain-identifier ltd.intention.talky.ios --source "$WORK/$f" --destination "Documents/$f" -q >/dev/null 2>&1 || {
    echo "✗ 音檔傳不進手機（Talky 裝了嗎？手機解鎖了嗎？）"
    exit 1
  }
  EXTRA=()
  [ "$TRANSLATE" = 1 ] && EXTRA=(-TalkyTranslate "${TARGETS[$i]}")
  echo "── 第 $((i + 1)) 句（念的是）：$s${EXTRA[1]:+　→ ${EXTRA[1]}}"
  # 90 秒沒結束就放棄（perl alarm：macOS 沒有 timeout 指令）
  perl -e 'alarm shift; exec @ARGV' 90 xcrun devicectl device process launch --console --terminate-existing \
    --device "$UDID" ltd.intention.talky.ios -- -TalkyFeedFile "$f" -TalkyExitAfterTest ${MODE_ARGS[@]+"${MODE_ARGS[@]}"} ${EXTRA[@]+"${EXTRA[@]}"} 2>&1 \
    | grep "TALKY-TEST" | sed 's/^.*TALKY-TEST /   /' || echo "   （沒拿到輸出：手機要解鎖，而且要是 Debug 版）"
done
