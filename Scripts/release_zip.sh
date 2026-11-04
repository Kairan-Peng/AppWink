#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

APP_EXECUTABLE_NAME=${APP_EXECUTABLE_NAME:-${APP_NAME:-AppWink}}
APP_DISPLAY_NAME=${APP_DISPLAY_NAME:-AppWink}
APP_BUNDLE_NAME=${APP_BUNDLE_NAME:-$APP_DISPLAY_NAME}
APP_PATH="$ROOT_DIR/${APP_BUNDLE_NAME}.app"
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT_DIR/dist"}
RELEASE_ARCHES=${RELEASE_ARCHES:-"arm64 x86_64"}
ALLOW_UNSAFE_DISTRIBUTION=${ALLOW_UNSAFE_DISTRIBUTION:-0}
APP_IDENTITY=${APP_IDENTITY:-}
SIGNING_MODE=${SIGNING_MODE:-}
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

usage() {
  cat <<EOF
Usage: $(basename "$0") [--output-dir PATH] [--zip-name NAME] [--arches "arm64 x86_64"] [--allow-unsafe-distribution]

Build a versioned AppWink release zip under dist/.

Options:
  --output-dir PATH              Output directory. Default: ${OUTPUT_DIR}
  --zip-name NAME               Zip basename without .zip. Default: ${ZIP_NAME}
  --arches "arm64 x86_64"       Space-separated architectures. Default: ${RELEASE_ARCHES}
  --allow-unsafe-distribution   Allow adhoc or unsigned output when APP_IDENTITY is not set.
  --help                        Show this help.

Environment:
  APP_IDENTITY                  Developer ID Application certificate common name.
  SIGNING_MODE                  Passed to package_app.sh. Use developer-id or adhoc.
  SPARKLE_FEED_URL              Feed URL written into AppWink.app Info.plist for Sparkle.
  SPARKLE_PUBLIC_ED_KEY         Public EdDSA key written into AppWink.app Info.plist for Sparkle.
  SPARKLE_ENABLE_AUTOMATIC_CHECKS
                                Optional Sparkle default for automatic update checks.
  SPARKLE_ALLOW_AUTOMATIC_UPDATES
                                Optional Sparkle default for automatic download / install behavior.
  OUTPUT_DIR                    Same as --output-dir.
  ZIP_NAME                      Same as --zip-name.
  RELEASE_ARCHES                Same as --arches.
  ALLOW_UNSAFE_DISTRIBUTION=1   Required if APP_IDENTITY is unset.

Examples:
  APP_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/release_zip.sh
  ALLOW_UNSAFE_DISTRIBUTION=1 SIGNING_MODE=adhoc ./Scripts/release_zip.sh
EOF
}

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

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
    --arches)
      RELEASE_ARCHES="$2"
      shift 2
      ;;
    --allow-unsafe-distribution)
      ALLOW_UNSAFE_DISTRIBUTION=1
      shift
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

if [[ -n "$APP_IDENTITY" ]]; then
  EFFECTIVE_SIGNING_MODE=${SIGNING_MODE:-developer-id}
else
  if [[ "$ALLOW_UNSAFE_DISTRIBUTION" != "1" ]]; then
    fail "APP_IDENTITY is required for release distribution. Set ALLOW_UNSAFE_DISTRIBUTION=1 only for local non-user-facing smoke builds."
  fi
  EFFECTIVE_SIGNING_MODE=${SIGNING_MODE:-adhoc}
  warn "Building an unsafe distribution artifact with SIGNING_MODE=${EFFECTIVE_SIGNING_MODE}. Do not ship this to external users."
fi

[[ "$EFFECTIVE_SIGNING_MODE" != "none" ]] || fail "release_zip.sh requires a signed bundle; use package_app.sh directly for unsigned local builds."

mkdir -p "$OUTPUT_DIR"

ZIP_PATH="$OUTPUT_DIR/${ZIP_NAME}.zip"
SHA_PATH="${ZIP_PATH}.sha256"

log "==> Packaging ${APP_BUNDLE_NAME}.app"
SIGNING_MODE="$EFFECTIVE_SIGNING_MODE" \
ARCHES="$RELEASE_ARCHES" \
APP_EXECUTABLE_NAME="$APP_EXECUTABLE_NAME" \
APP_DISPLAY_NAME="$APP_DISPLAY_NAME" \
APP_BUNDLE_NAME="$APP_BUNDLE_NAME" \
APP_IDENTITY="$APP_IDENTITY" \
SPARKLE_FEED_URL="$SPARKLE_FEED_URL" \
SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
SPARKLE_ENABLE_AUTOMATIC_CHECKS="$SPARKLE_ENABLE_AUTOMATIC_CHECKS" \
SPARKLE_ALLOW_AUTOMATIC_UPDATES="$SPARKLE_ALLOW_AUTOMATIC_UPDATES" \
"$ROOT_DIR/Scripts/package_app.sh" release

if [[ ! -d "$APP_PATH" ]]; then
  fail "Expected app bundle at $APP_PATH"
fi

log "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

log "==> Creating release zip"
rm -f "$ZIP_PATH" "$SHA_PATH"
ditto -c -k --keepParent --sequesterRsrc "$APP_PATH" "$ZIP_PATH"
(
  cd "$(dirname "$ZIP_PATH")"
  shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$SHA_PATH")"
)

log "Created $ZIP_PATH"
log "Created $SHA_PATH"

if [[ -n "$APP_IDENTITY" ]]; then
  log "Next step: NOTARY_KEYCHAIN_PROFILE=<profile> ./Scripts/notarize_app.sh --zip-name ${ZIP_NAME}"
fi
