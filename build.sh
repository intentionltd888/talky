#!/bin/bash
# Talky — build：編譯 → 組 .app → 帶引擎 → 圖示 → ad-hoc 簽名
#
# 這支腳本只做「能跑的 .app」，不出 DMG、不做公證、不帶任何品牌資產。
# 引擎（whisper／llama）從 vendor/ 拿；vendor/ 不進 git，用 scripts/vendor-fetch.sh 準備。
# 全程不刪檔（覆蓋式重建；要換掉的舊夾一律 mv 走，不 rm）。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Talky"
BUILD="${TALKY_BUILD_DIR:-build}"  # 可用 TALKY_BUILD_DIR 換目錄（build/ 的 app 正在跑時另開一個建）
APP="$BUILD/$APP_NAME.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

mkdir -p "$MACOS" "$RES" "$BUILD"

echo "── 1/5 編譯 Swift ──"
swiftc -O app/Sources/*.swift -o "$MACOS/$APP_NAME" \
  -framework AppKit -framework SwiftUI -framework AVFoundation \
  -framework UserNotifications -framework ServiceManagement \
  -target arm64-apple-macos14.0

cp app/Info.plist "$APP/Contents/Info.plist"

echo "── 1b 品牌資產（Resources/Brand，見 app/Resources/Brand/TRADEMARK.md）──"
mkdir -p "$RES/Brand"
cp app/Resources/Brand/* "$RES/Brand/"
# AGENTS.md 隨包（使用者只拿到 DMG 時，他的 AI 也讀得到；「貼給你的 AI」那段話指向這個路徑）
cp AGENTS.md "$RES/AGENTS.md"

echo "── 2/5 App 圖示（六臂米字 Logo，程式畫）──"
# 每次重畫（1 秒；病史＝只在缺檔時畫，改了 make-icon.swift 之後 Dock 一直是舊圖）
swift scripts/make-icon.swift "$BUILD/icon_1024.png" >/dev/null
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz "$BUILD/icon_1024.png" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  dbl=$((sz * 2))
  sips -z $dbl $dbl "$BUILD/icon_1024.png" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"

echo "── 3/5 引擎 ──"
copy_engine() { # vendor 子夾, 目的名
  local src="vendor/$1" dest="$RES/$2"
  if [ ! -d "$src" ]; then
    echo "   ⚠ 找不到 $src——這顆 .app 不會自帶引擎"
    echo "     開發機請先跑：bash scripts/vendor-fetch.sh"
    return 0
  fi
  # 舊夾整個移開重建：cp 蓋不掉「檔名不同的舊殘留」（不同版號的 dylib 混包會直接崩）
  if [ -d "$dest" ]; then
    chmod -R u+w "$dest"
    mv "$dest" "$(mktemp -d)/$2-superseded"
  fi
  mkdir -p "$dest"
  cp "$src"/* "$dest/"
  chmod u+w "$dest"/*
  echo "   $2：$(ls "$dest" | wc -l | tr -d ' ') 檔"
}
copy_engine whisper whisper
copy_engine llama llama

echo "── 4/5 簽名 ──"
xattr -cr "$APP" 2>/dev/null || true
# 預設 ad-hoc（"-"）：這支是中性建置腳本，不去翻你的鑰匙圈、不假設你有任何憑證。
# 代價＝每次重編後系統會重問一次麥克風與輔助使用權限，那是正常的。
# 有自己的憑證就自己指定：TALKY_SIGN_ID="Apple Development: 你" bash build.sh
# 沒指定就找這台有沒有 Developer ID：有就用，沒有才 ad-hoc。
# 病史＝ad-hoc 每次重編簽名都不同，系統設定裡「輔助使用」看起來是開的、對新 binary 卻無效，精靈永遠打不了勾。
# 憑證不在預設搜尋鏈時（例：登入鑰匙圈被系統換新，Developer ID 留在舊的那顆）：
#   TALKY_SIGN_KEYCHAIN=~/Library/Keychains/<舊鑰匙圈>.keychain-db bash build.sh   （那顆要先在「鑰匙圈存取」解鎖）
SIGN_KC="${TALKY_SIGN_KEYCHAIN:-}"
KC_OPT=()
[ -n "$SIGN_KC" ] && KC_OPT=(--keychain "$SIGN_KC")
SIGN_ID="${TALKY_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning ${SIGN_KC:+"$SIGN_KC"} 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')
  SIGN_ID="${SIGN_ID:--}"
fi
# 注意展開寫法 ${HARDEN[@]+"${HARDEN[@]}"}：bash 3.2（macOS 內建）在 set -u 下
# 展開空陣列會直接 unbound variable 中止腳本
HARDEN=()
if [ "$SIGN_ID" = "-" ]; then
  echo "   簽名身分：ad-hoc"
else
  HARDEN=(--options runtime --timestamp)
  echo "   簽名身分：$SIGN_ID（hardened runtime）"
fi
find "$APP" \( -name "*.dylib" -o -name "*.so" \) -exec codesign --force ${HARDEN[@]+"${HARDEN[@]}"} ${KC_OPT[@]+"${KC_OPT[@]}"} -s "$SIGN_ID" {} \; 2>/dev/null || true
for bin in "$RES/whisper/whisper-server" "$RES/whisper/whisper-cli" "$RES/llama/llama-server"; do
  [ -f "$bin" ] && codesign --force ${HARDEN[@]+"${HARDEN[@]}"} ${KC_OPT[@]+"${KC_OPT[@]}"} -s "$SIGN_ID" "$bin"
done
if [ "$SIGN_ID" = "-" ]; then
  codesign --force --deep -s "-" "$APP"
else
  codesign --force ${HARDEN[@]+"${HARDEN[@]}"} ${KC_OPT[@]+"${KC_OPT[@]}"} --entitlements app/Talky.entitlements -s "$SIGN_ID" "$APP"
fi

echo "── 5/5 出貨閘 ──"
# 閘一：包內二進位的 minos 不得高於 LSMinimumSystemVersion。
# 病史＝在新 macOS 上抓來的引擎 minos 是新系統版號，舊系統機器 Metal 載入永遠失敗，
# 辨識悄悄退 CPU、慢 30 倍。這是「看不出來」的那種壞。
MINOS_REQ=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" app/Info.plist 2>/dev/null || echo "14.0")
MINOS_BAD=0
MINOS_N=0
while IFS= read -r f; do
  file -b "$f" 2>/dev/null | grep -q "Mach-O" || continue
  m=$(otool -l "$f" 2>/dev/null | grep -A4 LC_BUILD_VERSION | grep minos | head -1 | awk '{print $2}')
  [ -z "$m" ] && continue
  MINOS_N=$((MINOS_N + 1))
  if [ "$(printf '%s\n%s\n' "$MINOS_REQ" "$m" | sort -V | tail -1)" != "$MINOS_REQ" ]; then
    echo "   ✗ ${f#"$APP"/}：minos $m > $MINOS_REQ"
    MINOS_BAD=1
  fi
done < <(find "$APP" -type f)
if [ "$MINOS_BAD" = "1" ]; then
  echo "✗ 擋下：包內有高於 macOS $MINOS_REQ 的二進位。用 scripts/vendor-build.sh 重編引擎後再跑一次"
  exit 1
fi

# 閘二：引擎夾內每個 @rpath／@loader_path 依賴都要同夾有實檔、不得有包外絕對依賴。
# 病史＝只拷了帶版號的實檔、漏了相容名（symlink 沒跟到），開發機因編譯樹還在而假通過，
# 乾淨機一律載不到引擎。
DEP_BAD=0
for d in "$RES/whisper" "$RES/llama"; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    file -b "$f" 2>/dev/null | grep -q "Mach-O" || continue
    while IFS= read -r dep; do
      [ -e "$d/$dep" ] || { echo "   ✗ $(basename "$f") 需要 $dep，包內沒有"; DEP_BAD=1; }
    done < <(otool -L "$f" 2>/dev/null | awk '$1 ~ /^@(rpath|loader_path)\// {print $1}' | sed -E 's#^@(rpath|loader_path)/##' | sort -u)
    while IFS= read -r dep; do
      echo "   ✗ $(basename "$f") 連到包外絕對路徑依賴：$dep"
      DEP_BAD=1
    done < <(otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -E '^/(opt|usr/local)/' || true)
  done
done
if [ "$DEP_BAD" = "1" ]; then
  echo "✗ 擋下：引擎依賴在乾淨機上解不開——先跑 scripts/vendor-build.sh"
  exit 1
fi
echo "   ✓ minos 驗過 $MINOS_N 檔、引擎依賴閉包乾淨"

VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BLD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
echo "✅ 完成：$PWD/$APP（v$VER build $BLD）"
echo "   跑跑看：open $APP    或    $MACOS/$APP_NAME --doctor"
