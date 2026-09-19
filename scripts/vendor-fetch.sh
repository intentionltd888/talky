#!/bin/bash
# vendor-fetch.sh — 把語音／整理引擎放進 vendor/（build.sh 會從那裡拿）
#
# 兩條路，照順序試：
#   ① 這台機器上已經有一份組好的引擎（姊妹專案的 vendor/whisper＋vendor/llama）→ 直接複製，幾秒
#   ② 沒有 → 呼叫 scripts/vendor-build.sh 從源碼編（M 系列約 10–20 分鐘）
#
# 想指定來源：TALKY_ENGINE_SRC=/path/to/vendor bash scripts/vendor-fetch.sh
# vendor/ 不進 git（引擎二進位不散布在原始碼倉裡）。
set -euo pipefail
cd "$(dirname "$0")/.."

want_dirs=(whisper llama)

have_all() { # 目錄
  local base="$1"
  for d in "${want_dirs[@]}"; do
    [ -d "$base/$d" ] || return 1
  done
  return 0
}

SRC="${TALKY_ENGINE_SRC:-}"

if [ -n "$SRC" ] && ! have_all "$SRC"; then
  echo "✗ TALKY_ENGINE_SRC=$SRC 裡沒有 whisper/ 與 llama/"
  exit 1
fi

# 自動找：同一層或再下一層的姊妹專案（它們的 vendor/ 已經組好且驗過）
if [ -z "$SRC" ]; then
  for c in ../*/vendor ../*/*/vendor ../*/*/*/vendor; do
    [ -d "$c" ] || continue
    if have_all "$c"; then
      SRC="$c"
      break
    fi
  done
fi

if [ -n "$SRC" ]; then
  echo "── 從本機既有引擎複製：$SRC ──"
  for d in "${want_dirs[@]}"; do
    dest="vendor/$d"
    if [ -d "$dest" ]; then
      chmod -R u+w "$dest"
      mv "$dest" "$(mktemp -d)/$d-superseded"   # 舊夾移開不刪
    fi
    mkdir -p "$dest"
    cp "$SRC/$d"/* "$dest/"
    chmod u+w "$dest"/*
    echo "   $d：$(ls "$dest" | wc -l | tr -d ' ') 檔"
  done
else
  echo "── 找不到現成引擎，改從源碼編 ──"
  bash scripts/vendor-build.sh
fi

echo "── 驗證 ──"
BAD=0
for d in "${want_dirs[@]}"; do
  [ -d "vendor/$d" ] || { echo "   ✗ vendor/$d 不存在"; BAD=1; continue; }
  n=$(ls "vendor/$d" | wc -l | tr -d ' ')
  [ "$n" -ge 5 ] || { echo "   ✗ vendor/$d 只有 $n 檔，看起來不完整"; BAD=1; }
  for f in "vendor/$d"/*; do
    file -b "$f" 2>/dev/null | grep -q "Mach-O" || continue
    while IFS= read -r dep; do
      echo "   ✗ $(basename "$f") 連到包外絕對路徑：$dep"
      BAD=1
    done < <(otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -E '^/(opt|usr/local)/' || true)
  done
done
[ "$BAD" = "1" ] && { echo "✗ 引擎包不乾淨，請改跑 bash scripts/vendor-build.sh"; exit 1; }
echo "✅ vendor/ 就緒，接著跑：bash build.sh"
