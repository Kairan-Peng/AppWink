#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

SPARKLE_CHECKOUT_MANIFEST="$ROOT_DIR/.build/checkouts/Sparkle/Package.swift"
LOCAL_SPARKLE_DIR=${LOCAL_SPARKLE_DIR:-"$ROOT_DIR/.local-artifacts/sparkle"}
LOCAL_SPARKLE_ZIP="$LOCAL_SPARKLE_DIR/Sparkle-for-Swift-Package-Manager.zip"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--output-dir PATH]

Download and extract the official Sparkle SwiftPM binary artifact into a local
cache that AppWink can use when SwiftPM hangs on the remote binary target.

Options:
  --output-dir PATH   Local artifact directory. Default: ${LOCAL_SPARKLE_DIR}
  --help              Show this help.

This script reads the Sparkle tag and checksum from .build/checkouts/Sparkle/Package.swift.
If that checkout is missing, it first runs 'swift package resolve' to fetch the source package.
EOF
}

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '%s\n' "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      LOCAL_SPARKLE_DIR="$2"
      LOCAL_SPARKLE_ZIP="$LOCAL_SPARKLE_DIR/Sparkle-for-Swift-Package-Manager.zip"
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

if [[ ! -f "$SPARKLE_CHECKOUT_MANIFEST" ]]; then
  log "==> Resolving Sparkle source package metadata"
  swift package resolve
fi

[[ -f "$SPARKLE_CHECKOUT_MANIFEST" ]] || fail "Sparkle package manifest not found at $SPARKLE_CHECKOUT_MANIFEST"

SPARKLE_TAG=$(sed -n 's/^let tag = "\(.*\)"$/\1/p' "$SPARKLE_CHECKOUT_MANIFEST")
SPARKLE_CHECKSUM=$(sed -n 's/^let checksum = "\(.*\)"$/\1/p' "$SPARKLE_CHECKOUT_MANIFEST")

[[ -n "$SPARKLE_TAG" ]] || fail "Unable to determine Sparkle tag from $SPARKLE_CHECKOUT_MANIFEST"
[[ -n "$SPARKLE_CHECKSUM" ]] || fail "Unable to determine Sparkle checksum from $SPARKLE_CHECKOUT_MANIFEST"

SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_TAG}/Sparkle-for-Swift-Package-Manager.zip"

mkdir -p "$LOCAL_SPARKLE_DIR"

log "==> Downloading Sparkle ${SPARKLE_TAG}"
curl -L --fail --output "$LOCAL_SPARKLE_ZIP" "$SPARKLE_URL"

ACTUAL_CHECKSUM=$(shasum -a 256 "$LOCAL_SPARKLE_ZIP" | awk '{print $1}')
if [[ "$ACTUAL_CHECKSUM" != "$SPARKLE_CHECKSUM" ]]; then
  fail "Sparkle checksum mismatch. Expected ${SPARKLE_CHECKSUM}, got ${ACTUAL_CHECKSUM}."
fi

find "$LOCAL_SPARKLE_DIR" -mindepth 1 -maxdepth 1 ! -name "$(basename "$LOCAL_SPARKLE_ZIP")" -exec rm -rf {} +

log "==> Extracting local Sparkle artifact cache"
ditto -x -k "$LOCAL_SPARKLE_ZIP" "$LOCAL_SPARKLE_DIR"

[[ -d "$LOCAL_SPARKLE_DIR/Sparkle.xcframework" ]] || fail "Sparkle.xcframework was not extracted into $LOCAL_SPARKLE_DIR"
[[ -x "$LOCAL_SPARKLE_DIR/bin/generate_appcast" ]] || fail "Sparkle bin tools were not extracted into $LOCAL_SPARKLE_DIR/bin"

log "Prepared local Sparkle artifact at $LOCAL_SPARKLE_DIR"
log "Use it with: APPWINK_USE_LOCAL_SPARKLE_ARTIFACT=1 swift build"
