#!/bin/bash
# vendor-build.sh — 從源碼重編 whisper.cpp＋llama.cpp 成「macOS 14 起可用」的可攜引擎包
#
# 為什麼不從 brew 拷：brew bottle 是「當前 macOS」編的，在新系統上抓到的整套二進位 minos
# 都是新系統版號，Metal 後端會用到新 API，在舊系統上 dlopen 永遠失敗 → 辨識悄悄退 CPU、
# 慢 30 倍。app 宣告 LSMinimumSystemVersion 14.0，引擎就必須用同一個部署目標編。
#
# 版本鎖定＝行為不飄移。產物：vendor/whisper/、vendor/llama/（build.sh 會吃這兩夾）。
# 用法：bash scripts/vendor-build.sh   （之後跑 bash build.sh）
# 需要：cmake、git、Xcode 命令列工具。M 系列約 10–20 分鐘。
set -euo pipefail
cd "$(dirname "$0")/.."

WHISPER_TAG="v1.9.1"
LLAMA_TAG="b10050"
TARGET="14.0"
SRC="${VENDOR_SRC:-/tmp/talky-engine-src}"   # 源碼可拋棄（by tag 可重抓）；產物才進 vendor/
JOBS=$(sysctl -n hw.ncpu)

# __FILE__（斷言與記錄訊息）會把編譯當下的源碼絕對路徑寫進二進位——建置機的路徑不該跟著出貨。
# 兩道保險：SRC 預設就在中性的 /tmp 底下；再用 -ffile-prefix-map 把它換成 "."，換了 SRC 也不漏。
PREFIX_MAP="-ffile-prefix-map=$SRC=."

CMAKE_COMMON=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_C_FLAGS="$PREFIX_MAP"
  -DCMAKE_CXX_FLAGS="$PREFIX_MAP"
  -DCMAKE_OBJC_FLAGS="$PREFIX_MAP"
  -DCMAKE_OBJCXX_FLAGS="$PREFIX_MAP"
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$TARGET"
  -DBUILD_SHARED_LIBS=ON
  -DGGML_METAL=ON
  -DGGML_METAL_EMBED_LIBRARY=ON
  -DGGML_BACKEND_DL=ON
  -DGGML_CPU_ALL_VARIANTS=ON
  -DGGML_NATIVE=OFF
)

mkdir -p "$SRC"

clone() { # repo url, tag, dir
  local url="$1" tag="$2" dir="$3"
  if [ ! -d "$dir/.git" ]; then
    git clone --branch "$tag" --depth 1 "$url" "$dir"
  else
    (cd "$dir" && git fetch --depth 1 origin tag "$tag" && git checkout -q "$tag")
  fi
}

echo "── 1/4 whisper.cpp $WHISPER_TAG ──"
clone https://github.com/ggml-org/whisper.cpp "$WHISPER_TAG" "$SRC/whisper.cpp"
cmake -S "$SRC/whisper.cpp" -B "$SRC/whisper.cpp/build-t14" "${CMAKE_COMMON[@]}" \
  -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_BUILD_TESTS=OFF >/dev/null
cmake --build "$SRC/whisper.cpp/build-t14" -j "$JOBS" --target whisper-cli whisper-server >/dev/null

echo "── 2/4 llama.cpp $LLAMA_TAG ──"
clone https://github.com/ggml-org/llama.cpp "$LLAMA_TAG" "$SRC/llama.cpp"
# SSL 從根拔掉：localhost 的整理伺服器不需要 TLS，而 cpp-httplib 一偵測到系統 openssl 就自動
# 連進來——那顆通常是新系統編的、帶絕對路徑、外部簽章，三重死。
cmake -S "$SRC/llama.cpp" -B "$SRC/llama.cpp/build-t14" "${CMAKE_COMMON[@]}" \
  -DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_CURL=OFF -DLLAMA_SERVER_SSL=OFF -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=TRUE >/dev/null
cmake --build "$SRC/llama.cpp/build-t14" -j "$JOBS" --target llama-server >/dev/null

# ── 組可攜包：主程式＋dylib/.so 閉包全拷平放，參照全改 @loader_path ──
assemble() { # build 樹, 主程式（空白分隔多個）, 目的夾
  local tree="$1" bins="$2" dest="$3"
  # 舊內容整夾移開（不刪；也防殘留混包）
  [ -d "$dest" ] && mv "$dest" "$(mktemp -d)/$(basename "$dest")-superseded"
  mkdir -p "$dest"
  local files=()
  for b in $bins; do files+=("$(find "$tree/bin" -name "$b" -type f | head -1)"); done
  while IFS= read -r f; do files+=("$f"); done \
    < <(find "$tree/bin" \( -name "*.dylib" -o -name "*.so" \) -type f)
  for f in "${files[@]}"; do
    [ -f "$f" ] || { echo "缺檔：$f"; exit 1; }
    cp -f "$f" "$dest/$(basename "$f")"
    chmod u+w "$dest/$(basename "$f")"
  done
  # 相容名補齊：CMake 產物的 libX.1.dylib 是 symlink、上面的 find -type f 收不到，
  # 但主程式與 dylib 互相參照全用這種相容名——缺了它只有開發機跑得動。實體複製、不留 symlink。
  while IFS= read -r ln; do
    tgt=$(readlink "$ln")
    real="$dest/$(basename "$tgt")"
    if [ -f "$real" ] && [ ! -e "$dest/$(basename "$ln")" ]; then
      cp -f "$real" "$dest/$(basename "$ln")"
      chmod u+w "$dest/$(basename "$ln")"
      echo "   相容名：$(basename "$ln") ← $(basename "$tgt")"
    fi
  done < <(find "$tree/bin" \( -name "*.dylib" -o -name "*.so" \) -type l)
  # 參照改寫：所有 @rpath／build 樹絕對路徑 → @loader_path/同名（檔案都在同一夾）
  for f in "$dest"/*; do
    case "$f" in *.dylib | *.so) install_name_tool -id "@loader_path/$(basename "$f")" "$f" 2>/dev/null ;; esac
    otool -L "$f" | tail -n +2 | awk '{print $1}' | while IFS= read -r dep; do
      local name; name=$(basename "$dep")
      if [ -f "$dest/$name" ] && [ "$name" != "$(basename "$f")" ]; then
        case "$dep" in @loader_path/*) ;; *) install_name_tool -change "$dep" "@loader_path/$name" "$f" 2>/dev/null ;; esac
      fi
    done
    # 絕對 rpath 一律換成 @loader_path（重複就刪）——build 樹路徑留在二進位裡＝開發機假通過。
    # 注意寫法：process substitution 而非管線，否則沒有 LC_RPATH 的檔會讓整條管線失敗、腳本靜靜中止。
    while IFS= read -r rp; do
      case "$rp" in
        /*) install_name_tool -rpath "$rp" "@loader_path" "$f" 2>/dev/null \
              || install_name_tool -delete_rpath "$rp" "$f" 2>/dev/null || true ;;
      esac
    done < <(otool -l "$f" 2>/dev/null | grep -A2 LC_RPATH | awk '/ path /{print $2}' || true)
    codesign -f -s - "$f" 2>/dev/null  # 改寫後補 ad-hoc 簽（arm64 沒簽名跑不動）；build.sh 會再重簽
  done
}

echo "── 3/4 組 vendor/whisper ──"
assemble "$SRC/whisper.cpp/build-t14" "whisper-cli whisper-server" "vendor/whisper"
echo "── 4/4 組 vendor/llama ──"
assemble "$SRC/llama.cpp/build-t14" "llama-server" "vendor/llama"

echo ""
echo "── 驗證：每檔 minos（必須全是 $TARGET）──"
BAD=0
for f in vendor/whisper/* vendor/llama/*; do
  m=$(otool -l "$f" 2>/dev/null | grep -A4 LC_BUILD_VERSION | grep minos | head -1 | awk '{print $2}')
  printf "   %-46s minos %s\n" "$(basename "$(dirname "$f")")/$(basename "$f")" "${m:-?}"
  [ "$m" = "$TARGET" ] || BAD=1
done
[ "$BAD" = "1" ] && { echo "✗ 有檔案不是 $TARGET"; exit 1; }
echo "✅ 引擎可攜包完成（macOS $TARGET+）。下一步：bash build.sh"
