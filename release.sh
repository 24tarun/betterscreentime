#!/usr/bin/env bash
set -euo pipefail

# One-shot macOS release helper:
# 1) Create DMG from a signed .app
# 2) Notarize DMG
# 3) Staple and validate
#
# Required:
# - A signed .app bundle (Developer ID)
# - Xcode command line tools (xcrun, hdiutil)
# - Apple notarization credentials
#
# Usage examples:
#   APP_PATH="~/Desktop/release/BetterScreenTime.app" \
#   APPLE_ID="you@example.com" TEAM_ID="ABCDE12345" APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
#   ./release.sh
#
#   # Or with keychain profile (recommended):
#   # xcrun notarytool store-credentials "notary-profile" --apple-id ... --team-id ... --password ...
#   APP_PATH="~/Desktop/release/BetterScreenTime.app" NOTARY_PROFILE="notary-profile" ./release.sh

APP_PATH="${APP_PATH:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/dist}"
VOL_NAME="${VOL_NAME:-BetterScreenTime}"
DMG_NAME="${DMG_NAME:-BetterScreenTime}"

APPLE_ID="${APPLE_ID:-}"
TEAM_ID="${TEAM_ID:-}"
APP_PASSWORD="${APP_PASSWORD:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -z "$APP_PATH" ]]; then
  echo "[error] APP_PATH is required (path to signed .app)."
  exit 1
fi

# Expand ~ and normalize
APP_PATH="${APP_PATH/#\~/$HOME}"

if [[ ! -d "$APP_PATH" || "${APP_PATH##*.}" != "app" ]]; then
  echo "[error] APP_PATH must point to an existing .app bundle. Got: $APP_PATH"
  exit 1
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  if [[ -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$APP_PASSWORD" ]]; then
    echo "[error] Provide NOTARY_PROFILE, or APPLE_ID + TEAM_ID + APP_PASSWORD."
    exit 1
  fi
fi

mkdir -p "$OUTPUT_DIR"
WORK_DIR="$(mktemp -d /tmp/bst-release.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

APP_BASENAME="$(basename "$APP_PATH")"
APP_NAME="${APP_BASENAME%.app}"
DMG_PATH="$OUTPUT_DIR/${DMG_NAME}.dmg"

echo "[1/6] Preparing staging folder..."
STAGE_DIR="$WORK_DIR/stage"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "[2/6] Creating DMG: $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null

echo "[3/6] Preflight Gatekeeper check..."
spctl -a -vv -t open "$DMG_PATH" || true

echo "[4/6] Submitting DMG for notarization..."
if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
else
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait
fi

echo "[5/6] Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "[6/6] Validating notarization + Gatekeeper..."
xcrun stapler validate "$DMG_PATH"
spctl -a -vv -t open "$DMG_PATH"

echo
echo "Release artifact ready: $DMG_PATH"
