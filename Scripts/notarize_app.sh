#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

LOCAL_SPARKLE_BIN_DIR="$ROOT_DIR/.local-artifacts/sparkle/bin"
DEFAULT_SPARKLE_BIN_DIR="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"

APP_EXECUTABLE_NAME=${APP_EXECUTABLE_NAME:-${APP_NAME:-AppWink}}
APP_DISPLAY_NAME=${APP_DISPLAY_NAME:-AppWink}
APP_BUNDLE_NAME=${APP_BUNDLE_NAME:-$APP_DISPLAY_NAME}
APP_PATH="$ROOT_DIR/${APP_BUNDLE_NAME}.app"
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT_DIR/dist"}
RELEASE_ARCHES=${RELEASE_ARCHES:-"arm64 x86_64"}
APP_IDENTITY=${APP_IDENTITY:-}
SIGNING_MODE=${SIGNING_MODE:-developer-id}
NOTARY_KEYCHAIN_PROFILE=${NOTARY_KEYCHAIN_PROFILE:-}
NOTARY_KEYCHAIN_PATH=${NOTARY_KEYCHAIN_PATH:-}
PACKAGE_FORMAT=${PACKAGE_FORMAT:-zip}
AUTO_PUBLISH_UPDATE_FEED=${AUTO_PUBLISH_UPDATE_FEED:-0}
PUBLIC_UPDATE_REPO_PATH=${PUBLIC_UPDATE_REPO_PATH:-}
APPCAST_BASE_URL=${APPCAST_BASE_URL:-}
if [[ -d "$LOCAL_SPARKLE_BIN_DIR" ]]; then
  SPARKLE_BIN_DIR=${SPARKLE_BIN_DIR:-"$LOCAL_SPARKLE_BIN_DIR"}
else
  SPARKLE_BIN_DIR=${SPARKLE_BIN_DIR:-"$DEFAULT_SPARKLE_BIN_DIR"}
fi
ED_KEY_FILE=${ED_KEY_FILE:-}
SPARKLE_KEYCHAIN_ACCOUNT=${SPARKLE_KEYCHAIN_ACCOUNT:-ed25519}
SPARKLE_FEED_URL=${SPARKLE_FEED_URL:-}
SPARKLE_PUBLIC_ED_KEY=${SPARKLE_PUBLIC_ED_KEY:-}
SPARKLE_ENABLE_AUTOMATIC_CHECKS=${SPARKLE_ENABLE_AUTOMATIC_CHECKS:-}
SPARKLE_ALLOW_AUTOMATIC_UPDATES=${SPARKLE_ALLOW_AUTOMATIC_UPDATES:-}

if [[ -f "$ROOT_DIR/version.env" ]]; then
  source "$ROOT_DIR/version.env"
else
  MARKETING_VERSION=${MARKETING_VERSION:-0.1.0}
  BUILD_NUMBER=${BUILD_NUMBER:-1}
fi

ZIP_NAME=${ZIP_NAME:-"${APP_BUNDLE_NAME}-v${MARKETING_VERSION}-build${BUILD_NUMBER}-mac"}
ZIP_NAME="${ZIP_NAME%.zip}"
DMG_NAME=${DMG_NAME:-"${APP_BUNDLE_NAME}-v${MARKETING_VERSION}-build${BUILD_NUMBER}-mac"}
DMG_NAME="${DMG_NAME%.dmg}"
SOURCE_ZIP="$OUTPUT_DIR/${ZIP_NAME}.zip"
SOURCE_SHA="${SOURCE_ZIP}.sha256"
NOTARIZED_ZIP="$OUTPUT_DIR/${ZIP_NAME}-notarized.zip"
NOTARIZED_SHA="${NOTARIZED_ZIP}.sha256"
SOURCE_DMG="$OUTPUT_DIR/${DMG_NAME}.dmg"
SOURCE_DMG_SHA="${SOURCE_DMG}.sha256"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--output-dir PATH] [--zip-name NAME] [--dmg-name NAME] [--arches "arm64 x86_64"] [--keychain-profile NAME] [--keychain PATH] [--package-format zip|dmg]

Build, notarize, staple, and package AppWink for external distribution.

Options:
  --output-dir PATH         Output directory. Default: ${OUTPUT_DIR}
  --zip-name NAME           Zip basename without .zip. Default: ${ZIP_NAME}
  --dmg-name NAME           DMG basename without .dmg. Default: ${DMG_NAME}
  --arches "arm64 x86_64"   Space-separated architectures. Default: ${RELEASE_ARCHES}
  --keychain-profile NAME   Stored notarytool keychain profile. Required.
  --keychain PATH           Keychain file path for notarytool profile lookup.
  --package-format VALUE    zip or dmg. Default: ${PACKAGE_FORMAT}
  --help                    Show this help.

Environment:
  APP_IDENTITY              Developer ID Application certificate common name. Required.
  NOTARY_KEYCHAIN_PROFILE   Same as --keychain-profile.
  NOTARY_KEYCHAIN_PATH      Same as --keychain.
  SIGNING_MODE              Passed through to release_zip.sh. Default: developer-id.
  PACKAGE_FORMAT            Same as --package-format.
  OUTPUT_DIR                Same as --output-dir.
  ZIP_NAME                  Same as --zip-name.
  DMG_NAME                  Same as --dmg-name.
  RELEASE_ARCHES            Same as --arches.
  SPARKLE_FEED_URL          Feed URL written into AppWink.app Info.plist for Sparkle.
  SPARKLE_PUBLIC_ED_KEY     Public EdDSA key written into AppWink.app Info.plist for Sparkle.
  SPARKLE_ENABLE_AUTOMATIC_CHECKS
                            Optional Sparkle default for automatic update checks.
  SPARKLE_ALLOW_AUTOMATIC_UPDATES
                            Optional Sparkle default for automatic download / install behavior.
  AUTO_PUBLISH_UPDATE_FEED=1
                            After a notarized DMG completes, export release notes and stage the update feed into PUBLIC_UPDATE_REPO_PATH.
  PUBLIC_UPDATE_REPO_PATH   Local checkout path for the public updates repository.
  APPCAST_BASE_URL          Public base URL serving appcast.xml, downloads/, and release-notes/.
  SPARKLE_BIN_DIR           Directory containing generate_appcast. Default: ${SPARKLE_BIN_DIR}
  ED_KEY_FILE               Private EdDSA key file for generate_appcast.
  SPARKLE_KEYCHAIN_ACCOUNT  Keychain account for generate_appcast. Default: ${SPARKLE_KEYCHAIN_ACCOUNT}

Example:
  APP_IDENTITY="Developer ID Application: Your Name (TEAMID)" \\
  NOTARY_KEYCHAIN_PROFILE="appwink-notary" \\
  ./Scripts/notarize_app.sh
EOF
}

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

submit_for_notarization() {
  local artifact_path=$1

  if [[ -n "$NOTARY_KEYCHAIN_PATH" ]]; then
    xcrun notarytool submit "$artifact_path" \
      --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
      --keychain "$NOTARY_KEYCHAIN_PATH" \
      --wait
  else
    xcrun notarytool submit "$artifact_path" \
      --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
      --wait
  fi
}

refresh_source_zip() {
  rm -f "$SOURCE_ZIP" "$SOURCE_SHA"
  ditto -c -k --keepParent --sequesterRsrc "$APP_PATH" "$SOURCE_ZIP"
  (
    cd "$(dirname "$SOURCE_ZIP")"
    shasum -a 256 "$(basename "$SOURCE_ZIP")" > "$(basename "$SOURCE_SHA")"
  )
}

validate_app_bundle() {
  local app_path=$1

  xcrun stapler validate "$app_path"
  codesign --verify --deep --strict --verbose=2 "$app_path"
  spctl -a -vv "$app_path"
}

validate_dmg_app_bundle() {
  local dmg_path=$1
  local mount_dir
  local app_in_dmg
  local status=0

  mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/appwink-dmg-validate.XXXXXX")"

  if ! hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg_path" >/dev/null; then
    rm -rf "$mount_dir"
    return 1
  fi

  app_in_dmg="$mount_dir/${APP_BUNDLE_NAME}.app"
  if [[ ! -d "$app_in_dmg" ]]; then
    printf 'ERROR: Expected app bundle inside DMG at %s\n' "$app_in_dmg" >&2
    status=1
  else
    validate_app_bundle "$app_in_dmg" || status=$?
  fi

  hdiutil detach "$mount_dir" >/dev/null || true
  rm -rf "$mount_dir"
  return "$status"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --zip-name)
      ZIP_NAME="${2%.zip}"
      shift 2
      ;;
    --dmg-name)
      DMG_NAME="${2%.dmg}"
      shift 2
      ;;
    --arches)
      RELEASE_ARCHES="$2"
      shift 2
      ;;
    --keychain-profile)
      NOTARY_KEYCHAIN_PROFILE="$2"
      shift 2
      ;;
    --keychain)
      NOTARY_KEYCHAIN_PATH="$2"
      shift 2
      ;;
    --package-format)
      PACKAGE_FORMAT="$2"
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

SOURCE_ZIP="$OUTPUT_DIR/${ZIP_NAME}.zip"
SOURCE_SHA="${SOURCE_ZIP}.sha256"
NOTARIZED_ZIP="$OUTPUT_DIR/${ZIP_NAME}-notarized.zip"
NOTARIZED_SHA="${NOTARIZED_ZIP}.sha256"
SOURCE_DMG="$OUTPUT_DIR/${DMG_NAME}.dmg"
SOURCE_DMG_SHA="${SOURCE_DMG}.sha256"

if [[ -z "$APP_IDENTITY" ]]; then
  fail "APP_IDENTITY is required for notarization."
fi

if [[ "$PACKAGE_FORMAT" != "zip" && "$PACKAGE_FORMAT" != "dmg" ]]; then
  fail "PACKAGE_FORMAT must be 'zip' or 'dmg'."
fi

if [[ -z "$NOTARY_KEYCHAIN_PROFILE" ]]; then
  fail "NOTARY_KEYCHAIN_PROFILE is required. Create one with: xcrun notarytool store-credentials ..."
fi

if ! xcrun --find notarytool >/dev/null 2>&1; then
  fail "xcrun notarytool is not available on this machine."
fi

if ! xcrun --find stapler >/dev/null 2>&1; then
  fail "xcrun stapler is not available on this machine."
fi

log "==> Building signed release app"
APP_IDENTITY="$APP_IDENTITY" \
SIGNING_MODE="$SIGNING_MODE" \
OUTPUT_DIR="$OUTPUT_DIR" \
ZIP_NAME="$ZIP_NAME" \
RELEASE_ARCHES="$RELEASE_ARCHES" \
SPARKLE_FEED_URL="$SPARKLE_FEED_URL" \
SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
SPARKLE_ENABLE_AUTOMATIC_CHECKS="$SPARKLE_ENABLE_AUTOMATIC_CHECKS" \
SPARKLE_ALLOW_AUTOMATIC_UPDATES="$SPARKLE_ALLOW_AUTOMATIC_UPDATES" \
"$ROOT_DIR/Scripts/release_zip.sh"

if [[ ! -f "$SOURCE_ZIP" ]]; then
  fail "Expected source zip at $SOURCE_ZIP"
fi

if [[ ! -d "$APP_PATH" ]]; then
  fail "Expected app bundle at $APP_PATH"
fi

if [[ "$PACKAGE_FORMAT" == "zip" ]]; then
  log "==> Submitting zip for notarization"
  submit_for_notarization "$SOURCE_ZIP"

  log "==> Stapling notarization ticket to app"
  xcrun stapler staple "$APP_PATH"

  log "==> Validating stapled app"
  validate_app_bundle "$APP_PATH"

  log "==> Creating notarized release zip"
  rm -f "$NOTARIZED_ZIP" "$NOTARIZED_SHA"
  ditto -c -k --keepParent --sequesterRsrc "$APP_PATH" "$NOTARIZED_ZIP"
  (
    cd "$(dirname "$NOTARIZED_ZIP")"
    shasum -a 256 "$(basename "$NOTARIZED_ZIP")" > "$(basename "$NOTARIZED_SHA")"
  )

  log "Created $SOURCE_ZIP"
  log "Created $SOURCE_SHA"
  log "Created $NOTARIZED_ZIP"
  log "Created $NOTARIZED_SHA"
  log "Next step: upload $NOTARIZED_ZIP and $NOTARIZED_SHA to your release host."
else
  log "==> Submitting source zip for app notarization"
  submit_for_notarization "$SOURCE_ZIP"

  log "==> Stapling notarization ticket to app"
  xcrun stapler staple "$APP_PATH"

  log "==> Validating stapled app"
  validate_app_bundle "$APP_PATH"

  log "==> Refreshing source zip with stapled app"
  refresh_source_zip

  log "==> Creating release DMG"
  APP_PATH="$APP_PATH" \
  OUTPUT_DIR="$OUTPUT_DIR" \
  DMG_NAME="$DMG_NAME" \
  APP_BUNDLE_NAME="$APP_BUNDLE_NAME" \
  APP_DISPLAY_NAME="$APP_DISPLAY_NAME" \
  "$ROOT_DIR/Scripts/create_dmg.sh"

  if [[ ! -f "$SOURCE_DMG" ]]; then
    fail "Expected source DMG at $SOURCE_DMG"
  fi

  log "==> Submitting DMG for notarization"
  submit_for_notarization "$SOURCE_DMG"

  log "==> Stapling notarization ticket to DMG"
  xcrun stapler staple "$SOURCE_DMG"

  log "==> Validating stapled artifacts"
  validate_app_bundle "$APP_PATH"
  xcrun stapler validate "$SOURCE_DMG"
  validate_dmg_app_bundle "$SOURCE_DMG"
  hdiutil verify "$SOURCE_DMG"
  (
    cd "$(dirname "$SOURCE_DMG")"
    shasum -a 256 "$(basename "$SOURCE_DMG")" > "$(basename "$SOURCE_DMG_SHA")"
  )

  log "Created $SOURCE_ZIP"
  log "Created $SOURCE_SHA"
  log "Created $SOURCE_DMG"
  log "Created $SOURCE_DMG_SHA"

  if [[ "$AUTO_PUBLISH_UPDATE_FEED" == "1" ]]; then
    [[ -n "$PUBLIC_UPDATE_REPO_PATH" ]] || fail "PUBLIC_UPDATE_REPO_PATH is required when AUTO_PUBLISH_UPDATE_FEED=1"
    [[ -n "$APPCAST_BASE_URL" ]] || fail "APPCAST_BASE_URL is required when AUTO_PUBLISH_UPDATE_FEED=1"

    RELEASE_NOTES_OUTPUT_DIR="$OUTPUT_DIR/release-notes"
    PUBLISH_ARGS=(
      --public-repo-path "$PUBLIC_UPDATE_REPO_PATH"
      --artifact "$SOURCE_DMG"
      --checksum "$SOURCE_DMG_SHA"
      --release-notes "$RELEASE_NOTES_OUTPUT_DIR/${DMG_NAME}.html"
      --base-url "$APPCAST_BASE_URL"
      --public-ed-key "$SPARKLE_PUBLIC_ED_KEY"
      --sparkle-bin-dir "$SPARKLE_BIN_DIR"
      --keychain-account "$SPARKLE_KEYCHAIN_ACCOUNT"
    )

    if [[ -n "$ED_KEY_FILE" ]]; then
      PUBLISH_ARGS+=(--ed-key-file "$ED_KEY_FILE")
    fi

    "$ROOT_DIR/Scripts/export_release_notes.sh" \
      --version "$MARKETING_VERSION" \
      --archive-name "$DMG_NAME" \
      --output-dir "$RELEASE_NOTES_OUTPUT_DIR"

    "$ROOT_DIR/Scripts/publish_update_feed.sh" "${PUBLISH_ARGS[@]}"
  else
    log "Next step: PUBLIC_UPDATE_REPO_PATH=<public-repo-checkout> APPCAST_BASE_URL=<public-base-url> ./Scripts/publish_update_feed.sh --artifact $SOURCE_DMG --checksum $SOURCE_DMG_SHA --release-notes dist/release-notes/${DMG_NAME}.html"
  fi
fi
