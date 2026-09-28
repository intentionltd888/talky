#!/bin/bash
# 在模擬器看 Talky 鍵盤各種狀態（開發用，Debug 版）：
#   bash ios/scripts/sim-keyboard.sh <狀態> [light|dark] [輸出檔.png] [app 參數…]
# 狀態：idle｜sleeping｜listening｜listening-tr｜working｜working-tr｜done｜done-tr｜hold
# （長按挑翻譯目標的畫面＝idle 加 app 參數 -TalkyDebugPicker）
# 做法：開 app 的鍵盤探針（-TalkyKeyboardProbe，叫出 Talky 鍵盤）→ 把想看的 state.json 寫進模擬器的 App Group
# → 用 notifyutil 叫鍵盤重讀 → 截圖。模擬器要先把 Talky 加進鍵盤清單（見 README「開發」）。
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
SIM=${SIM:-booted}
STATE=${1:-idle}
LOOK=${2:-light}
OUT=${3:-kb_${STATE}_${LOOK}.png}
shift $(( $# < 3 ? $# : 3 ))
GROUP=$(xcrun simctl get_app_container "$SIM" ltd.intention.talky.ios group.ltd.intention.talky)
xcrun simctl ui "$SIM" appearance "$LOOK"
xcrun simctl launch --terminate-running-process "$SIM" ltd.intention.talky.ios -TalkyKeyboardProbe talky "$@" >/dev/null
sleep 2.5
python3 - "$GROUP/Library/state.json" "$STATE" <<'PY'
import json, sys, time, uuid
path, st = sys.argv[1], sys.argv[2]
now = time.time() - 978307200  # Swift Date 的 JSON 預設＝2001-01-01 起算秒數
s = {"phase": "ready", "target": "keyboard", "readyUntil": now + 3600, "partial": "", "level": 0, "stamp": now}
said = "欸你今天下班之後有空嗎我想說請你吃飯就是上次你幫我那個忙"
zh = "你今天下班之後有空嗎？我想請你吃飯，謝謝上次你幫我的忙。"
if st == "sleeping": s.update(phase="off", readyUntil=None)
if st.startswith("listening"): s.update(phase="listening", partial=said[:18], level=0.55)
if st.startswith("working"): s.update(phase="working", partial=said)
if st.endswith("-tr") and st != "done-tr": s.update(out="th:girl")
if st in ("done", "done-tr", "hold"): s.update(phase="done", resultID=str(uuid.uuid4()), path="claude")
if st == "done": s.update(result=zh, raw=said)
if st == "done-tr": s.update(result="เธอวันนี้เลิกงานแล้วว่างไหมครับ เราอยากเลี้ยงข้าวเธอหน่อยนะ ขอบคุณที่ช่วยเราไว้ครั้งก่อนครับ",
                             raw=zh, back="妳今天下班後有空嗎？我想請妳吃個飯喔，謝謝妳上次幫我。", lang="th")
if st == "hold": s.update(result=zh, raw=zh, hold=True, path="light", message="沒翻成（連不到 Mac mini），先給你中文、沒有自動打上")
json.dump({k: v for k, v in s.items() if v is not None}, open(path, "w"), ensure_ascii=False)
PY
xcrun simctl spawn "$SIM" notifyutil -p ltd.intention.talky.state
sleep 1.2
xcrun simctl io "$SIM" screenshot "$OUT" >/dev/null 2>&1
echo "$OUT"
