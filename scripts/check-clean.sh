#!/bin/bash
# check-clean.sh — 公開前的清洗總掃
#
# 兩層：
#   ① 通用檢查（寫在這裡）：金鑰形狀、使用者家目錄的絕對路徑、引擎二進位有沒有進 git、
#      出貨的 app 裡有沒有留下建置機的路徑。
#   ② 專案自己的禁用字（不寫在這裡）：一行一條放在倉外的規則檔，預設
#      ~/.config/talky/clean-patterns.tsv，可用 TALKY_CLEAN_PATTERNS 指到別處。
#      格式：正則<TAB>說明<TAB>白名單檔案（空白分隔，可省略）；# 開頭是註解。
#      沒有規則檔就只跑 ①。
# 綠燈＝可以公開；紅燈＝列出檔案與行號。
set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0
RULES="${TALKY_CLEAN_PATTERNS:-$HOME/.config/talky/clean-patterns.tsv}"

# 掃描範圍：git 追蹤的檔案（vendor/ 與 build/ 已被 .gitignore 排除）
if git rev-parse --git-dir >/dev/null 2>&1; then
  FILES=$(git ls-files)
else
  FILES=$(find . -type f -not -path "./.git/*" -not -path "./vendor/*" -not -path "./build/*" | sed 's|^\./||')
fi

check() { # 正則, 說明, [白名單檔案…]
  local pattern="$1" label="$2"
  shift 2
  local hits=""
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    local skip=0
    for w in "$@"; do
      [ "$f" = "$w" ] && skip=1
    done
    [ "$skip" = "1" ] && continue
    local m
    m=$(grep -nE "$pattern" "$f" 2>/dev/null || true)
    [ -n "$m" ] && hits="$hits
$(echo "$m" | sed "s|^|  $f:|")"
  done <<< "$FILES"
  if [ -n "$hits" ]; then
    echo "✗ $label"
    echo "$hits" | sed '/^$/d'
    FAIL=1
  else
    printf "  ok   %s\n" "$label"
  fi
}

echo "Talky clean check"

# ── ① 通用檢查 ──
# 金鑰形狀（防手滑）。白名單：BrainsView.swift＝金鑰欄的 placeholder 文字；本檔＝規則字串自己
check 'sk-ant-[A-Za-z0-9]|ghp_[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY|SUPublicEDKey' '金鑰形狀' app/Sources/BrainsView.swift scripts/check-clean.sh
# 使用者家目錄的絕對路徑（文件裡要寫路徑就用 ~ 或 <你的帳號>）
check '/Users/[a-z][a-z0-9_-]+/' '家目錄絕對路徑'

# 引擎二進位不得進 git
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git ls-files | grep -qE '^vendor/'; then
    echo "✗ vendor/ 被加進 git 了（引擎二進位不散布在原始碼倉裡）"
    FAIL=1
  else
    printf "  ok   %s\n" "vendor/ 沒進 git"
  fi
fi

# 出貨的 app：二進位裡不得留建置機的路徑（__FILE__ 會把編譯當下的源碼絕對路徑寫進引擎；
# 引擎要在中性路徑編，見 scripts/vendor-build.sh）。還沒 build 就跳過。
APP="${TALKY_BUILD_DIR:-build}/Talky.app"
if [ -d "$APP" ]; then
  BIN_HITS=0
  while IFS= read -r -d '' f; do
    n=$(strings - "$f" 2>/dev/null | grep -cE '/Users/[a-z][a-z0-9_-]+/|-Users-[a-z]' || true)
    if [ "${n:-0}" -gt 0 ]; then
      echo "  ${f#"$APP"/}: $n 處"
      BIN_HITS=$((BIN_HITS + n))
    fi
  done < <(find "$APP/Contents" -type f \( -perm -u+x -o -name "*.dylib" -o -name "*.so" \) -print0)
  if [ "$BIN_HITS" -gt 0 ]; then
    echo "✗ 出貨二進位裡有建置機路徑（共 $BIN_HITS 處，見上）——在中性路徑重編引擎：bash scripts/vendor-build.sh"
    FAIL=1
  else
    printf "  ok   %s\n" "出貨二進位沒有建置機路徑"
  fi
else
  printf "  --   %s\n" "還沒 build，略過二進位檢查"
fi

# ── ② 專案自己的禁用字（倉外規則檔）──
if [ -f "$RULES" ]; then
  while IFS=$'\t' read -r pattern label white; do
    case "$pattern" in '' | '#'*) continue ;; esac
    # shellcheck disable=SC2086
    check "$pattern" "${label:-自訂規則}" ${white:-}
  done < "$RULES"
else
  printf "  --   %s\n" "沒有自訂規則檔，只跑通用檢查"
fi

echo ""
if [ "$FAIL" = "0" ]; then
  echo "✅ 乾淨，可以公開"
  exit 0
fi
echo "✗ 有東西沒清乾淨（見上）"
exit 1
