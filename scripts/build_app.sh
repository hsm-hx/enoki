#!/usr/bin/env bash
# Enoki (朔と栞) の .app を組み立てる。
#   UNIVERSAL=1          … arm64 + x86_64 のユニバーサルバイナリにする
#   CODESIGN_IDENTITY=…  … 署名 ID（既定はアドホック署名 "-"）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Enoki"
CONFIG="release"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"
RESOURCE_BUNDLE="Enoki_Enoki.bundle"
ICON_SRC="$ROOT/Sources/Enoki/Resources/AppIcon/icon-1024.png"

SWIFT_FLAGS=(-c "$CONFIG")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  SWIFT_FLAGS+=(--arch arm64 --arch x86_64)
fi

echo "==> swift build ${SWIFT_FLAGS[*]}"
swift build "${SWIFT_FLAGS[@]}"

BIN_PATH="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"
echo "==> bin path: $BIN_PATH"

echo "==> .app を作成: $APP"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$BIN_PATH/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

if [[ -d "$BIN_PATH/$RESOURCE_BUNDLE" ]]; then
  cp -R "$BIN_PATH/$RESOURCE_BUNDLE" "$RES_DIR/$RESOURCE_BUNDLE"
else
  echo "!! リソースバンドル $RESOURCE_BUNDLE が $BIN_PATH に見つかりません" >&2
  exit 1
fi

echo "==> アイコンを生成"
if [[ -f "$ICON_SRC" ]]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"
  rm -rf "$(dirname "$ICONSET")"
else
  echo "!! アイコン $ICON_SRC が見つかりません（アイコン無しで続行）" >&2
fi

echo "==> codesign"
codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" "$APP"

echo ""
echo "完成: $APP"
echo "  起動:      open \"$APP\""
echo "  インストール: make install   (~/Applications へコピー)"
