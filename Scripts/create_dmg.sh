#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

APP_DISPLAY_NAME=${APP_DISPLAY_NAME:-AppWink}
APP_BUNDLE_NAME=${APP_BUNDLE_NAME:-$APP_DISPLAY_NAME}
APP_PATH=${APP_PATH:-"$ROOT_DIR/${APP_BUNDLE_NAME}.app"}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT_DIR/dist"}

if [[ -f "$ROOT_DIR/version.env" ]]; then
  source "$ROOT_DIR/version.env"
else
  MARKETING_VERSION=${MARKETING_VERSION:-0.1.0}
  BUILD_NUMBER=${BUILD_NUMBER:-1}
fi

DMG_NAME=${DMG_NAME:-"${APP_BUNDLE_NAME}-v${MARKETING_VERSION}-build${BUILD_NUMBER}-mac"}
DMG_NAME="${DMG_NAME%.dmg}"
VOLUME_NAME=${VOLUME_NAME:-$APP_BUNDLE_NAME}

usage() {
  cat <<EOF
Usage: $(basename "$0") [--app-path PATH] [--output-dir PATH] [--dmg-name NAME] [--volume-name NAME]

Create a simple drag-to-Applications DMG from an existing AppWink.app.

Options:
  --app-path PATH         Path to the .app bundle. Default: ${APP_PATH}
  --output-dir PATH       Output directory. Default: ${OUTPUT_DIR}
  --dmg-name NAME         DMG basename without .dmg. Default: ${DMG_NAME}
  --volume-name NAME      Mounted volume name. Default: ${VOLUME_NAME}
  --help                  Show this help.

Environment:
  APP_PATH                Same as --app-path.
  OUTPUT_DIR              Same as --output-dir.
  DMG_NAME                Same as --dmg-name.
  VOLUME_NAME             Same as --volume-name.

Example:
  ./Scripts/create_dmg.sh
EOF
}

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path)
      APP_PATH="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --dmg-name)
      DMG_NAME="${2%.dmg}"
      shift 2
      ;;
    --volume-name)
      VOLUME_NAME="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

if [[ ! -d "$APP_PATH" ]]; then
  fail "Expected app bundle at ${APP_PATH}. Run ./Scripts/package_app.sh or ./Scripts/release_zip.sh first."
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  fail "hdiutil is not available on this machine."
fi

mkdir -p "$OUTPUT_DIR"

DMG_PATH="$OUTPUT_DIR/${DMG_NAME}.dmg"
SHA_PATH="${DMG_PATH}.sha256"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/appwink-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

log "==> Preparing DMG staging folder"
ditto "$APP_PATH" "$STAGING_DIR/${APP_BUNDLE_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

log "==> Creating DMG"
rm -f "$DMG_PATH" "$SHA_PATH"
hdiutil create \
  -ov \
  -format UDZO \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  "$DMG_PATH"

log "==> Verifying DMG"
hdiutil verify "$DMG_PATH"
(
  cd "$(dirname "$DMG_PATH")"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$SHA_PATH")"
)

log "Created $DMG_PATH"
log "Created $SHA_PATH"
