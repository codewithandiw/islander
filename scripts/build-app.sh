#!/usr/bin/env bash
# Builds build/Islander.app from the Swift package and the bundled media adapter.
# Usage: scripts/build-app.sh [release|debug]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
ADAPTER_DIR="$ROOT/vendor/mediaremote-adapter"
# Pinned so builds are repeatable. Update deliberately after testing a newer commit.
ADAPTER_REPO="https://github.com/ungive/mediaremote-adapter.git"
ADAPTER_COMMIT="0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd"
APP="$ROOT/build/Islander.app"

if [ -d "/Applications/Xcode.app/Contents/Developer" ] && [ -z "${DEVELOPER_DIR:-}" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [ ! -d "$ADAPTER_DIR/.git" ]; then
  echo "==> Fetching mediaremote-adapter"
  git clone "$ADAPTER_REPO" "$ADAPTER_DIR"
  git -C "$ADAPTER_DIR" checkout --quiet "$ADAPTER_COMMIT"
fi

if [ ! -d "$ADAPTER_DIR/build/MediaRemoteAdapter.framework" ]; then
  echo "==> Building MediaRemoteAdapter.framework"
  cmake -S "$ADAPTER_DIR" -B "$ADAPTER_DIR/build" -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build "$ADAPTER_DIR/build" >/dev/null
fi

echo "==> Building Islander ($CONFIG)"
swift build --package-path "$ROOT" -c "$CONFIG"
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Islander" "$APP/Contents/MacOS/Islander"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# Regenerate with: swift scripts/make-icon.swift
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ADAPTER_DIR/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp -R "$ADAPTER_DIR/build/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"
if [ -d "$BIN_DIR/Islander_Islander.bundle" ]; then
  cp -R "$BIN_DIR/Islander_Islander.bundle" "$APP/Contents/Resources/"
fi
if [ -d "$ROOT/Sources/Islander/Resources/Sounds" ]; then
  cp -R "$ROOT/Sources/Islander/Resources/Sounds" "$APP/Contents/Resources/"
fi

# Ad-hoc signature. macOS may ask for audio permission again after each rebuild.
codesign --force --deep --sign - "$APP" >/dev/null

echo "==> Done: $APP"
