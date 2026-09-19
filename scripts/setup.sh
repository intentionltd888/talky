#!/bin/bash
# setup.sh — 從零開始的 Mac 一鍵備齊 Talky 的環境（給終端機派的朋友；不會終端機的人直接開 app，精靈會帶）
#
# 做什麼（每一步都先檢查、有就跳過、全程不刪東西）：
#   1. Talky.app：如果桌面／下載夾有 Talky-*.dmg 或旁邊有 Talky.app，幫你裝進 /Applications
#   2. 整理大腦（擇一即可，用你自己的訂閱額度，不用 API 金鑰）：
#      - Claude Code：沒有就用官方安裝腳本裝（不需要 Node）；裝完要你自己跑一次 `claude` 登入
#      - ChatGPT 桌面版（自帶 Codex）：沒有就打開下載頁；裝好登入即可
#      - Ollama（全在本機）：有 Homebrew 就 brew 裝，沒有就打開下載頁；然後拉 qwen3:4b
#   3. 印出這台的體檢（記憶體、磁碟、模型）
# 用法：bash setup.sh            （全部）
#      bash setup.sh --claude    （只裝 Claude Code）   --chatgpt   --ollama   --app
set -uo pipefail

want() { [ $# -eq 0 ] && return 0; for a in "$@"; do [ "$a" = "$WANT" ] && return 0; done; return 1; }
ARGS=("$@"); ALL=$([ ${#ARGS[@]} -eq 0 ] && echo 1 || echo 0)
has() { case " ${ARGS[*]} " in *" $1 "*) return 0;; esac; [ "$ALL" = 1 ]; }

echo "Talky 環境準備（$(sw_vers -productVersion)，$(sysctl -n hw.memsize | awk '{printf "%.0fGB", $1/1073741824}') 記憶體）"
[ "$(uname -m)" = "arm64" ] || { echo "✗ 這台不是 Apple 晶片（Talky v1 只支援 M1 以上）"; exit 1; }

# ── 1. app ──
if has --app; then
  if [ -d /Applications/Talky.app ]; then
    echo "ok  Talky.app 已在 /Applications"
  else
    DMG=$(ls -t "$HOME"/Downloads/Talky-*.dmg "$HOME"/Desktop/Talky-*.dmg 2>/dev/null | head -1)
    if [ -n "$DMG" ]; then
      echo "──  找到 $DMG，安裝中…"
      MNT=$(hdiutil attach -nobrowse -readonly "$DMG" | awk -F'\t' '/\/Volumes\// {print $NF}')
      if [ -d "$MNT/Talky.app" ]; then
        ditto "$MNT/Talky.app" /Applications/Talky.app && echo "ok  已裝進 /Applications/Talky.app"
      fi
      hdiutil detach "$MNT" >/dev/null 2>&1
    elif [ -d "$(dirname "$0")/../build/Talky.app" ]; then
      ditto "$(dirname "$0")/../build/Talky.app" /Applications/Talky.app && echo "ok  已從 build/ 裝進 /Applications"
    else
      echo "缺  找不到 Talky-*.dmg（放到下載夾或桌面再跑一次），或先 bash build.sh"
    fi
  fi
fi

# ── 2a. Claude Code ──
if has --claude; then
  if command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]; then
    echo "ok  Claude Code 已裝（$(command -v claude || echo "$HOME/.local/bin/claude")）"
  else
    echo "──  安裝 Claude Code（官方腳本，不需要 Node）…"
    curl -fsSL https://claude.ai/install.sh | bash && echo "ok  Claude Code 裝好了" || echo "缺  Claude Code 安裝失敗（網路？）"
  fi
  echo "    → 之後在終端機跑一次：claude   （登入你的 Claude 訂閱）"
fi

# ── 2b. ChatGPT 桌面版（Codex） ──
if has --chatgpt; then
  if [ -x /Applications/ChatGPT.app/Contents/Resources/codex ]; then
    echo "ok  ChatGPT 桌面版已裝（自帶 Codex）：$(/Applications/ChatGPT.app/Contents/Resources/codex login status 2>&1 | head -1)"
  else
    echo "缺  沒有 ChatGPT 桌面版——已打開下載頁，裝好、登入你的 ChatGPT 就能當整理大腦"
    open "https://chatgpt.com/download" 2>/dev/null || true
  fi
fi

# ── 2c. Ollama ──
if has --ollama; then
  if [ -d /Applications/Ollama.app ] || command -v ollama >/dev/null 2>&1; then
    echo "ok  Ollama 已裝"
  elif command -v brew >/dev/null 2>&1; then
    echo "──  brew 安裝 Ollama…"
    brew install --cask ollama && echo "ok  Ollama 裝好了" || echo "缺  brew 裝 Ollama 失敗"
  else
    echo "缺  沒有 Ollama 也沒有 Homebrew——已打開下載頁"
    open "https://ollama.com/download/mac" 2>/dev/null || true
  fi
  if command -v ollama >/dev/null 2>&1; then
    (ollama list 2>/dev/null | grep -q "qwen3:4b") && echo "ok  模型 qwen3:4b 已在" || { echo "──  拉模型 qwen3:4b（約 2.5GB）…"; ollama pull qwen3:4b || true; }
  fi
fi

# ── 3. 體檢 ──
FREE=$(df -g "$HOME" | awk 'NR==2 {print $4}')
echo "──  磁碟剩 ${FREE}GB（語音模型 1.5GB；內建整理模型再 2.5GB）"
[ -f "$HOME/Library/Application Support/WereHear/models/ggml-large-v3-turbo.bin" ] && echo "ok  語音模型已在（同一家會議記錄 app 下載過，Talky 會直接借用）"
[ -f "$HOME/Library/Application Support/Talky/models/ggml-large-v3-turbo.bin" ] && echo "ok  語音模型已在（Talky 自己的）"
echo
echo "下一步：打開 /Applications/Talky.app，照七步精靈走（權限→模型→大腦→快捷鍵→試講）。"
