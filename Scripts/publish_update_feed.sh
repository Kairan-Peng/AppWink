#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

LOCAL_SPARKLE_BIN_DIR="$ROOT_DIR/.local-artifacts/sparkle/bin"
DEFAULT_SPARKLE_BIN_DIR="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"

PUBLIC_UPDATE_REPO_PATH=${PUBLIC_UPDATE_REPO_PATH:-}
ARTIFACT_PATH=${ARTIFACT_PATH:-}
CHECKSUM_PATH=${CHECKSUM_PATH:-}
RELEASE_NOTES_PATH=${RELEASE_NOTES_PATH:-}
APPCAST_BASE_URL=${APPCAST_BASE_URL:-}
APPCAST_FILENAME=${APPCAST_FILENAME:-appcast.xml}
DOWNLOADS_DIR_NAME=${DOWNLOADS_DIR_NAME:-downloads}
RELEASE_NOTES_DIR_NAME=${RELEASE_NOTES_DIR_NAME:-release-notes}
if [[ -d "$LOCAL_SPARKLE_BIN_DIR" ]]; then
  SPARKLE_BIN_DIR=${SPARKLE_BIN_DIR:-"$LOCAL_SPARKLE_BIN_DIR"}
else
  SPARKLE_BIN_DIR=${SPARKLE_BIN_DIR:-"$DEFAULT_SPARKLE_BIN_DIR"}
fi
ED_KEY_FILE=${ED_KEY_FILE:-}
SPARKLE_KEYCHAIN_ACCOUNT=${SPARKLE_KEYCHAIN_ACCOUNT:-ed25519}
FULL_RELEASE_NOTES_URL=${FULL_RELEASE_NOTES_URL:-}
PRODUCT_LINK=${PRODUCT_LINK:-}
SPARKLE_PUBLIC_ED_KEY=${SPARKLE_PUBLIC_ED_KEY:-}
KEEP_ONLY_LATEST=${KEEP_ONLY_LATEST:-1}
MAXIMUM_DELTAS=${MAXIMUM_DELTAS:-0}

usage() {
  cat <<EOF
Usage: $(basename "$0") --public-repo-path PATH --artifact PATH --checksum PATH --release-notes PATH --base-url URL --public-ed-key KEY [options]

Stage a notarized Sparkle archive, release notes, and appcast into a local public updates repo checkout.

Required:
  --public-repo-path PATH   Local checkout path of the public updates repository.
  --artifact PATH           Notarized DMG or zip to publish.
  --checksum PATH           Matching .sha256 file for the archive.
  --release-notes PATH      HTML release notes file. Basename must match the archive basename.
  --base-url URL            Public base URL that serves appcast.xml, downloads/, and release-notes/.
  --public-ed-key KEY       Public EdDSA key embedded into the shipped app build.

Optional:
  --appcast-name NAME       Appcast filename. Default: ${APPCAST_FILENAME}
  --downloads-dir NAME      Downloads directory name. Default: ${DOWNLOADS_DIR_NAME}
  --release-notes-dir NAME  Release-notes directory name. Default: ${RELEASE_NOTES_DIR_NAME}
  --sparkle-bin-dir PATH    Directory containing generate_appcast. Default: ${SPARKLE_BIN_DIR}
  --ed-key-file PATH        Private EdDSA key file for generate_appcast.
  --keychain-account NAME   Keychain account for generate_appcast. Default: ${SPARKLE_KEYCHAIN_ACCOUNT}
  --full-release-notes-url URL
  --product-link URL
  --keep-only-latest 0|1    Keep only the newest published archive and release notes in the public repo. Default: ${KEEP_ONLY_LATEST}
  --maximum-deltas N       Max delta items to generate for the latest update. Default: ${MAXIMUM_DELTAS}
  --help                    Show this help.
EOF
}

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '%s\n' "$*"; }
trim_whitespace() { awk '{$1=$1;print}'; }

validate_path_component() {
  local name="$1"
  local value="$2"
  [[ -n "$value" && "$value" != "." && "$value" != ".." && "$value" != */* ]] || \
    fail "$name must be a single non-empty path component."
  [[ "$value" != .* ]] || fail "$name must not be a hidden or Git control path."
}

strip_delta_entries_if_disabled() {
  if [[ "$MAXIMUM_DELTAS" == "0" ]]; then
    /usr/bin/perl -0pi -e 's/\n\s*<sparkle:deltas>.*?<\/sparkle:deltas>//sg' "$1"
  fi
}

prune_public_repo_to_latest_release() {
  local checksum_basename
  checksum_basename=$(basename "$CHECKSUM_PATH")

  find "$DOWNLOADS_DIR" -maxdepth 1 -type f \
    ! -name ".gitkeep" \
    ! -name "$ARTIFACT_BASENAME" \
    ! -name "$checksum_basename" \
    -delete

  find "$RELEASE_NOTES_DIR" -maxdepth 1 -type f \
    ! -name ".gitkeep" \
    ! -name "$EXPECTED_RELEASE_NOTES_BASENAME" \
    -delete
}

copy_if_needed() {
  local source_path="$1"
  local destination_path="$2"

  if [[ -e "$destination_path" && "$source_path" -ef "$destination_path" ]]; then
    return 0
  fi

  cp "$source_path" "$destination_path"
}

resolve_keychain_public_key() {
  "$SPARKLE_BIN_DIR/generate_keys" --account "$SPARKLE_KEYCHAIN_ACCOUNT" -p | tr -d '\r' | tail -n 1 | trim_whitespace
}

resolve_private_file_public_key() {
  local private_key_file="$1"

  if [[ "$private_key_file" == "-" ]]; then
    fail "Cannot validate --ed-key-file - against SPARKLE_PUBLIC_ED_KEY. Use a real private key file or keychain account."
  fi

  [[ -f "$private_key_file" ]] || fail "Private EdDSA key file not found at $private_key_file"

  PRIVATE_KEY_FILE="$private_key_file" /usr/bin/swift - <<'SWIFT'
import CryptoKit
import Foundation

let environment = ProcessInfo.processInfo.environment
let path = environment["PRIVATE_KEY_FILE"] ?? ""
let encodedSeed = try String(contentsOfFile: path, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)

guard let seed = Data(base64Encoded: encodedSeed) else {
    fputs("Failed to decode the exported private EdDSA key as base64.\n", stderr)
    exit(1)
}

guard seed.count == 32 else {
    fputs("Only 32-byte exported EdDSA seed files can be validated automatically. Re-export the Sparkle key with generate_keys -x or use a keychain account.\n", stderr)
    exit(1)
}

let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
print(privateKey.publicKey.rawRepresentation.base64EncodedString())
SWIFT
}

validate_public_key_match() {
  local resolved_public_key

  if [[ -n "$ED_KEY_FILE" ]]; then
    resolved_public_key=$(resolve_private_file_public_key "$ED_KEY_FILE")
  else
    resolved_public_key=$(resolve_keychain_public_key)
  fi

  resolved_public_key=$(printf '%s' "$resolved_public_key" | trim_whitespace)

  if [[ -z "$resolved_public_key" ]]; then
    fail "Unable to resolve the signing public key for appcast generation."
  fi

  if [[ "$resolved_public_key" != "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    fail "SPARKLE_PUBLIC_ED_KEY does not match the private key used for appcast signing."
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-repo-path)
      PUBLIC_UPDATE_REPO_PATH="$2"
      shift 2
      ;;
    --artifact)
      ARTIFACT_PATH="$2"
      shift 2
      ;;
    --checksum)
      CHECKSUM_PATH="$2"
      shift 2
      ;;
    --release-notes)
      RELEASE_NOTES_PATH="$2"
      shift 2
      ;;
    --base-url)
      APPCAST_BASE_URL="$2"
      shift 2
      ;;
    --public-ed-key)
      SPARKLE_PUBLIC_ED_KEY="$2"
      shift 2
      ;;
    --appcast-name)
      APPCAST_FILENAME="$2"
      shift 2
      ;;
    --downloads-dir)
      DOWNLOADS_DIR_NAME="$2"
      shift 2
      ;;
    --release-notes-dir)
      RELEASE_NOTES_DIR_NAME="$2"
      shift 2
      ;;
    --sparkle-bin-dir)
      SPARKLE_BIN_DIR="$2"
      shift 2
      ;;
    --ed-key-file)
      ED_KEY_FILE="$2"
      shift 2
      ;;
    --keychain-account)
      SPARKLE_KEYCHAIN_ACCOUNT="$2"
      shift 2
      ;;
    --full-release-notes-url)
      FULL_RELEASE_NOTES_URL="$2"
      shift 2
      ;;
    --product-link)
      PRODUCT_LINK="$2"
      shift 2
      ;;
    --keep-only-latest)
      KEEP_ONLY_LATEST="$2"
      shift 2
      ;;
    --maximum-deltas)
      MAXIMUM_DELTAS="$2"
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

[[ -n "$PUBLIC_UPDATE_REPO_PATH" ]] || fail "--public-repo-path is required"
[[ -n "$ARTIFACT_PATH" ]] || fail "--artifact is required"
[[ -n "$CHECKSUM_PATH" ]] || fail "--checksum is required"
[[ -n "$RELEASE_NOTES_PATH" ]] || fail "--release-notes is required"
[[ -n "$APPCAST_BASE_URL" ]] || fail "--base-url is required"
[[ -n "$SPARKLE_PUBLIC_ED_KEY" ]] || fail "--public-ed-key is required"
[[ -d "$PUBLIC_UPDATE_REPO_PATH" ]] || fail "Public updates repo checkout not found at $PUBLIC_UPDATE_REPO_PATH"
[[ -f "$ARTIFACT_PATH" ]] || fail "Artifact not found at $ARTIFACT_PATH"
[[ -f "$CHECKSUM_PATH" ]] || fail "Checksum not found at $CHECKSUM_PATH"
[[ -f "$RELEASE_NOTES_PATH" ]] || fail "Release notes file not found at $RELEASE_NOTES_PATH"
[[ -x "$SPARKLE_BIN_DIR/generate_appcast" ]] || fail "generate_appcast not found under $SPARKLE_BIN_DIR"
[[ -x "$SPARKLE_BIN_DIR/generate_keys" ]] || fail "generate_keys not found under $SPARKLE_BIN_DIR"

PUBLIC_UPDATE_REPO_ROOT=$(git -C "$PUBLIC_UPDATE_REPO_PATH" rev-parse --show-toplevel 2>/dev/null) || \
  fail "Public updates path is not a Git checkout: $PUBLIC_UPDATE_REPO_PATH"
PUBLIC_UPDATE_REPO_PHYSICAL=$(cd "$PUBLIC_UPDATE_REPO_PATH" && pwd -P)
PUBLIC_UPDATE_REPO_ROOT_PHYSICAL=$(cd "$PUBLIC_UPDATE_REPO_ROOT" && pwd -P)
[[ "$PUBLIC_UPDATE_REPO_PHYSICAL" == "$PUBLIC_UPDATE_REPO_ROOT_PHYSICAL" ]] || \
  fail "--public-repo-path must point to the Git checkout root, not a subdirectory."

validate_path_component "--downloads-dir" "$DOWNLOADS_DIR_NAME"
validate_path_component "--release-notes-dir" "$RELEASE_NOTES_DIR_NAME"
validate_path_component "--appcast-name" "$APPCAST_FILENAME"

DOWNLOADS_DIR_NAME_NORMALIZED=$(printf '%s' "$DOWNLOADS_DIR_NAME" | tr '[:upper:]' '[:lower:]')
RELEASE_NOTES_DIR_NAME_NORMALIZED=$(printf '%s' "$RELEASE_NOTES_DIR_NAME" | tr '[:upper:]' '[:lower:]')
APPCAST_FILENAME_NORMALIZED=$(printf '%s' "$APPCAST_FILENAME" | tr '[:upper:]' '[:lower:]')
[[ "$DOWNLOADS_DIR_NAME_NORMALIZED" != "$RELEASE_NOTES_DIR_NAME_NORMALIZED" ]] || \
  fail "--downloads-dir and --release-notes-dir must be different paths."
[[ "$APPCAST_FILENAME_NORMALIZED" != "$DOWNLOADS_DIR_NAME_NORMALIZED" && \
   "$APPCAST_FILENAME_NORMALIZED" != "$RELEASE_NOTES_DIR_NAME_NORMALIZED" ]] || \
  fail "--appcast-name must not collide with a publication directory."

DOWNLOADS_DIR="$PUBLIC_UPDATE_REPO_PATH/$DOWNLOADS_DIR_NAME"
RELEASE_NOTES_DIR="$PUBLIC_UPDATE_REPO_PATH/$RELEASE_NOTES_DIR_NAME"
APPCAST_PATH="$PUBLIC_UPDATE_REPO_PATH/$APPCAST_FILENAME"

[[ ! -L "$DOWNLOADS_DIR" ]] || fail "Downloads path must not be a symbolic link: $DOWNLOADS_DIR"
[[ ! -e "$DOWNLOADS_DIR" || -d "$DOWNLOADS_DIR" ]] || fail "Downloads path must be a directory: $DOWNLOADS_DIR"
[[ ! -L "$RELEASE_NOTES_DIR" ]] || fail "Release-notes path must not be a symbolic link: $RELEASE_NOTES_DIR"
[[ ! -e "$RELEASE_NOTES_DIR" || -d "$RELEASE_NOTES_DIR" ]] || \
  fail "Release-notes path must be a directory: $RELEASE_NOTES_DIR"
[[ ! -L "$APPCAST_PATH" ]] || fail "Appcast path must not be a symbolic link: $APPCAST_PATH"
[[ ! -e "$APPCAST_PATH" || -f "$APPCAST_PATH" ]] || fail "Appcast path must be a file: $APPCAST_PATH"

EXPECTED_CHECKSUM=$(awk 'NR == 1 { print tolower($1) }' "$CHECKSUM_PATH")
[[ "$EXPECTED_CHECKSUM" =~ ^[0-9a-f]{64}$ ]] || fail "Checksum file must start with one SHA-256 digest."
ACTUAL_CHECKSUM=$(shasum -a 256 "$ARTIFACT_PATH" | awk '{ print $1 }')
[[ "$ACTUAL_CHECKSUM" == "$EXPECTED_CHECKSUM" ]] || fail "Checksum does not match artifact: $ARTIFACT_PATH"

ARTIFACT_BASENAME=$(basename "$ARTIFACT_PATH")
ARTIFACT_STEM="${ARTIFACT_BASENAME%.*}"
EXPECTED_RELEASE_NOTES_BASENAME="${ARTIFACT_STEM}.html"
RELEASE_NOTES_BASENAME=$(basename "$RELEASE_NOTES_PATH")

if [[ "$RELEASE_NOTES_BASENAME" != "$EXPECTED_RELEASE_NOTES_BASENAME" ]]; then
  fail "Release notes basename must match the archive basename (${EXPECTED_RELEASE_NOTES_BASENAME})"
fi

validate_public_key_match

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$DOWNLOADS_DIR" "$RELEASE_NOTES_DIR"

if [[ "$KEEP_ONLY_LATEST" != "1" ]]; then
  if [[ -d "$DOWNLOADS_DIR" ]]; then
    ditto "$DOWNLOADS_DIR" "$TEMP_DIR"
  fi

  if [[ -d "$RELEASE_NOTES_DIR" ]]; then
    shopt -s nullglob
    for notes_file in "$RELEASE_NOTES_DIR"/*.html "$RELEASE_NOTES_DIR"/*.md "$RELEASE_NOTES_DIR"/*.txt; do
      cp "$notes_file" "$TEMP_DIR/"
    done
    shopt -u nullglob
  fi

  if [[ -f "$APPCAST_PATH" ]]; then
    cp "$APPCAST_PATH" "$TEMP_DIR/$APPCAST_FILENAME"
  fi
fi

cp "$ARTIFACT_PATH" "$TEMP_DIR/$ARTIFACT_BASENAME"
cp "$RELEASE_NOTES_PATH" "$TEMP_DIR/$EXPECTED_RELEASE_NOTES_BASENAME"

GENERATE_ARGS=(
  "--download-url-prefix" "${APPCAST_BASE_URL%/}/${DOWNLOADS_DIR_NAME}/"
  "--release-notes-url-prefix" "${APPCAST_BASE_URL%/}/${RELEASE_NOTES_DIR_NAME}/"
  "--account" "$SPARKLE_KEYCHAIN_ACCOUNT"
  "--maximum-deltas" "$MAXIMUM_DELTAS"
  "-o" "$TEMP_DIR/$APPCAST_FILENAME"
)

if [[ -n "$ED_KEY_FILE" ]]; then
  GENERATE_ARGS+=("--ed-key-file" "$ED_KEY_FILE")
fi

if [[ -n "$FULL_RELEASE_NOTES_URL" ]]; then
  GENERATE_ARGS+=("--full-release-notes-url" "$FULL_RELEASE_NOTES_URL")
fi

if [[ -n "$PRODUCT_LINK" ]]; then
  GENERATE_ARGS+=("--link" "$PRODUCT_LINK")
fi

if [[ "$KEEP_ONLY_LATEST" == "1" ]]; then
  GENERATE_ARGS+=("--maximum-versions" "1")
fi

"$SPARKLE_BIN_DIR/generate_appcast" "${GENERATE_ARGS[@]}" "$TEMP_DIR"
strip_delta_entries_if_disabled "$TEMP_DIR/$APPCAST_FILENAME"

copy_if_needed "$ARTIFACT_PATH" "$DOWNLOADS_DIR/$ARTIFACT_BASENAME"
copy_if_needed "$CHECKSUM_PATH" "$DOWNLOADS_DIR/$(basename "$CHECKSUM_PATH")"
copy_if_needed "$TEMP_DIR/$EXPECTED_RELEASE_NOTES_BASENAME" "$RELEASE_NOTES_DIR/$EXPECTED_RELEASE_NOTES_BASENAME"
copy_if_needed "$TEMP_DIR/$APPCAST_FILENAME" "$APPCAST_PATH"

if [[ "$KEEP_ONLY_LATEST" == "1" ]]; then
  prune_public_repo_to_latest_release
fi

log "Updated $APPCAST_PATH"
log "Copied $DOWNLOADS_DIR/$ARTIFACT_BASENAME"
log "Copied $DOWNLOADS_DIR/$(basename "$CHECKSUM_PATH")"
log "Copied $RELEASE_NOTES_DIR/$EXPECTED_RELEASE_NOTES_BASENAME"
