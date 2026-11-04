#!/usr/bin/env bash
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

APP_EXECUTABLE_NAME=${APP_EXECUTABLE_NAME:-${APP_NAME:-AppWink}}
APP_DISPLAY_NAME=${APP_DISPLAY_NAME:-AppWink}
APP_BUNDLE_NAME=${APP_BUNDLE_NAME:-$APP_DISPLAY_NAME}
BUNDLE_ID=${BUNDLE_ID:-com.kairanpeng.appwink}
MACOS_MIN_VERSION=${MACOS_MIN_VERSION:-14.0}
MENU_BAR_APP=${MENU_BAR_APP:-1}
SIGNING_MODE=${SIGNING_MODE:-}
APP_IDENTITY=${APP_IDENTITY:-}
SPARKLE_FEED_URL=${SPARKLE_FEED_URL:-}
SPARKLE_PUBLIC_ED_KEY=${SPARKLE_PUBLIC_ED_KEY:-}
SPARKLE_ENABLE_AUTOMATIC_CHECKS=${SPARKLE_ENABLE_AUTOMATIC_CHECKS:-}
SPARKLE_ALLOW_AUTOMATIC_UPDATES=${SPARKLE_ALLOW_AUTOMATIC_UPDATES:-}
APPWINK_USE_LOCAL_SPARKLE_ARTIFACT=${APPWINK_USE_LOCAL_SPARKLE_ARTIFACT:-}
LOCAL_SPARKLE_ARTIFACT_ROOT="$ROOT/.local-artifacts/sparkle"
LOCAL_SPARKLE_FRAMEWORK_PATH="$LOCAL_SPARKLE_ARTIFACT_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

[[ -n "$APP_BUNDLE_NAME" && "$APP_BUNDLE_NAME" != */* ]] || fail "APP_BUNDLE_NAME must be a non-empty file name without '/'."

[[ "$APP_EXECUTABLE_NAME" == "AppWink" ]] || fail "APP_EXECUTABLE_NAME must be AppWink."
APP_ENTITLEMENTS=${APP_ENTITLEMENTS:-$ROOT/Scripts/entitlements/AppWinkDirect.entitlements}
[[ -f "$APP_ENTITLEMENTS" ]] || fail "APP_ENTITLEMENTS does not exist: $APP_ENTITLEMENTS"

case "$SIGNING_MODE" in
  ""|none|adhoc)
    ;;
  developer-id)
    [[ -n "$APP_IDENTITY" ]] || fail "APP_IDENTITY is required when SIGNING_MODE=developer-id."
    ;;
  *)
    fail "Unsupported SIGNING_MODE: $SIGNING_MODE (expected none, adhoc, or developer-id)."
    ;;
esac

if [[ -f "$ROOT/version.env" ]]; then
  source "$ROOT/version.env"
else
  MARKETING_VERSION=${MARKETING_VERSION:-0.1.0}
  BUILD_NUMBER=${BUILD_NUMBER:-1}
fi

ARCH_LIST=( ${ARCHES:-} )
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  HOST_ARCH=$(uname -m)
  ARCH_LIST=("$HOST_ARCH")
fi

BUILD_PRODUCT_DIRS=()
BUILD_SCRATCH_PATHS=()
for ARCH in "${ARCH_LIST[@]}"; do
  if [[ -z "$APPWINK_USE_LOCAL_SPARKLE_ARTIFACT" && -d "$LOCAL_SPARKLE_ARTIFACT_ROOT/Sparkle.xcframework" ]]; then
    APPWINK_USE_LOCAL_SPARKLE_ARTIFACT=1
  fi

  if [[ "$APPWINK_USE_LOCAL_SPARKLE_ARTIFACT" == "1" && ! -d "$LOCAL_SPARKLE_ARTIFACT_ROOT/Sparkle.xcframework" ]]; then
    fail "APPWINK_USE_LOCAL_SPARKLE_ARTIFACT=1 but no local Sparkle artifact exists at $LOCAL_SPARKLE_ARTIFACT_ROOT. Run ./Scripts/prepare_local_sparkle_artifact.sh first."
  fi

  # Ask SwiftPM for its output directory. Xcode's build driver uses
  # Products/Debug (or Release), rather than the legacy architecture path.
  # Separate scratch directories also keep universal builds from replacing
  # the first architecture's product when the second architecture builds.
  SCRATCH_PATH="$ROOT/.build/packaging/$ARCH"
  BUILD_SCRATCH_PATHS+=("$SCRATCH_PATH")
  APPWINK_USE_LOCAL_SPARKLE_ARTIFACT="$APPWINK_USE_LOCAL_SPARKLE_ARTIFACT" \
    swift build --scratch-path "$SCRATCH_PATH" -c "$CONF" --arch "$ARCH" --product "$APP_EXECUTABLE_NAME" \
      -Xlinker -rpath -Xlinker '@executable_path/../Frameworks'
  BUILD_PRODUCT_DIRS+=("$(APPWINK_USE_LOCAL_SPARKLE_ARTIFACT="$APPWINK_USE_LOCAL_SPARKLE_ARTIFACT" \
    swift build --scratch-path "$SCRATCH_PATH" -c "$CONF" --arch "$ARCH" --show-bin-path)")
done

APP="$ROOT/${APP_BUNDLE_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

# Convert a source iconset/icon asset to Icon.icns if present (requires iconutil).
ICON_ICONSET_SOURCE="$ROOT/Icon.iconset"
ICON_COMPOSER_SOURCE="$ROOT/Icon.icon"
ICON_TARGET="$ROOT/Icon.icns"
if [[ -d "$ICON_ICONSET_SOURCE" ]]; then
  iconutil --convert icns --output "$ICON_TARGET" "$ICON_ICONSET_SOURCE"
elif [[ -f "$ICON_COMPOSER_SOURCE" ]]; then
  iconutil --convert icns --output "$ICON_TARGET" "$ICON_COMPOSER_SOURCE"
fi

LSUI_VALUE="false"
if [[ "$MENU_BAR_APP" == "1" ]]; then
  LSUI_VALUE="true"
fi

BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

validate_sparkle_feed_url() {
  local feed_url="$1"
  FEED_URL_TO_VALIDATE="$feed_url" /usr/bin/swift - <<'SWIFT' >/dev/null
import Foundation

let environment = ProcessInfo.processInfo.environment
let feedURL = environment["FEED_URL_TO_VALIDATE"] ?? ""

guard let url = URL(string: feedURL),
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      url.host?.isEmpty == false else {
    exit(1)
}
SWIFT
}

append_boolean_plist_entry() {
  local plist_path="$1"
  local key="$2"
  local value="$3"

  if [[ -z "$value" ]]; then
    return
  fi

  local normalized
  normalized=$(tr '[:upper:]' '[:lower:]' <<<"$value")
  case "$normalized" in
    1|true|yes)
      cat >> "$plist_path" <<PLIST
    <key>${key}</key><true/>
PLIST
      ;;
    0|false|no)
      cat >> "$plist_path" <<PLIST
    <key>${key}</key><false/>
PLIST
      ;;
    *)
      echo "ERROR: ${key} must be one of true/false/yes/no/1/0" >&2
      exit 1
      ;;
  esac
}

copy_bundle() {
  local source_path="$1"
  local destination_path="$2"
  rm -rf "$destination_path"
  ditto "$source_path" "$destination_path"
}

assert_signed_entitlement_absent() {
  local entitlements="$1"
  local key="$2"
  local keypath="${key//./\\.}"
  if /usr/bin/plutil -type "$keypath" "$entitlements" >/dev/null 2>&1; then
    fail "Signed app entitlement $key must be absent."
  fi
}

find_sparkle_framework() {
  local candidates=()
  if [[ "$APPWINK_USE_LOCAL_SPARKLE_ARTIFACT" == "1" ]]; then
    candidates+=("$LOCAL_SPARKLE_FRAMEWORK_PATH")
  else
    local index
    for index in "${!BUILD_PRODUCT_DIRS[@]}"; do
      candidates+=(
        "${BUILD_PRODUCT_DIRS[$index]}/Sparkle.framework"
        "${BUILD_SCRATCH_PATHS[$index]}/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
      )
    done
  fi

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

if [[ "$CONF" == "release" && -n "$APP_IDENTITY" ]]; then
  if [[ -z "$SPARKLE_FEED_URL" || -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    fail "SPARKLE_FEED_URL and SPARKLE_PUBLIC_ED_KEY are required for signed release packaging."
  fi
elif [[ -z "$SPARKLE_FEED_URL" || -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  warn "Sparkle feed URL / public EdDSA key not configured; update checks will remain disabled in this local package."
fi

if [[ -n "$SPARKLE_FEED_URL" ]] && ! validate_sparkle_feed_url "$SPARKLE_FEED_URL"; then
  fail "SPARKLE_FEED_URL must be a valid http or https URL."
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_EXECUTABLE_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
    <key>LSUIElement</key><${LSUI_VALUE}/>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
PLIST

if [[ -n "$SPARKLE_FEED_URL" ]]; then
  cat >> "$APP/Contents/Info.plist" <<PLIST
    <key>SUFeedURL</key><string>${SPARKLE_FEED_URL}</string>
PLIST
fi

if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  cat >> "$APP/Contents/Info.plist" <<PLIST
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_ED_KEY}</string>
PLIST
fi

append_boolean_plist_entry "$APP/Contents/Info.plist" "SUEnableAutomaticChecks" "$SPARKLE_ENABLE_AUTOMATIC_CHECKS"
append_boolean_plist_entry "$APP/Contents/Info.plist" "SUAllowsAutomaticUpdates" "$SPARKLE_ALLOW_AUTOMATIC_UPDATES"

cat >> "$APP/Contents/Info.plist" <<PLIST
</dict>
</plist>
PLIST

build_product_path() {
  local name="$1"
  local arch="$2"
  local index
  for index in "${!ARCH_LIST[@]}"; do
    if [[ "${ARCH_LIST[$index]}" == "$arch" ]]; then
      printf '%s/%s\n' "${BUILD_PRODUCT_DIRS[$index]}" "$name"
      return 0
    fi
  done
  fail "No build product directory resolved for $arch."
}

verify_binary_arches() {
  local binary="$1"; shift
  local expected=("$@")
  local actual
  actual=$(lipo -archs "$binary")
  local actual_count expected_count
  actual_count=$(wc -w <<<"$actual" | tr -d ' ')
  expected_count=${#expected[@]}
  if [[ "$actual_count" -ne "$expected_count" ]]; then
    echo "ERROR: $binary arch mismatch (expected: ${expected[*]}, actual: ${actual})" >&2
    exit 1
  fi
  for arch in "${expected[@]}"; do
    if [[ "$actual" != *"$arch"* ]]; then
      echo "ERROR: $binary missing arch $arch (have: ${actual})" >&2
      exit 1
    fi
  done
}

install_binary() {
  local name="$1"
  local dest="$2"
  local binaries=()
  for arch in "${ARCH_LIST[@]}"; do
    local src
    src=$(build_product_path "$name" "$arch")
    if [[ ! -f "$src" ]]; then
      echo "ERROR: Missing ${name} build for ${arch} at ${src}" >&2
      exit 1
    fi
    binaries+=("$src")
  done
  if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$dest"
  else
    cp "${binaries[0]}" "$dest"
  fi
  chmod +x "$dest"
  verify_binary_arches "$dest" "${ARCH_LIST[@]}"
}

install_binary "$APP_EXECUTABLE_NAME" "$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"

# Bundle app resources (if any).
APP_RESOURCES_DIR="$ROOT/Sources/$APP_EXECUTABLE_NAME/Resources"
if [[ -d "$APP_RESOURCES_DIR" ]]; then
  cp -R "$APP_RESOURCES_DIR/." "$APP/Contents/Resources/"
fi
cp "$ROOT/Scripts/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$ROOT/Scripts/licenses/Sparkle-2.9.1-LICENSE.txt" "$APP/Contents/Resources/Sparkle-2.9.1-LICENSE.txt"

# SwiftPM resource bundles are emitted next to the built binary.
PREFERRED_BUILD_DIR="$(dirname "$(build_product_path "$APP_EXECUTABLE_NAME" "${ARCH_LIST[0]}")")"
shopt -s nullglob
SWIFTPM_BUNDLES=("${PREFERRED_BUILD_DIR}/"*.bundle)
shopt -u nullglob
if [[ ${#SWIFTPM_BUNDLES[@]} -gt 0 ]]; then
  for bundle in "${SWIFTPM_BUNDLES[@]}"; do
    bundle_name=$(basename "$bundle")
    copy_bundle "$bundle" "$APP/Contents/Resources/$bundle_name"
  done
fi

# Embed frameworks if any exist in the build or artifact folders.
copied_frameworks=0
FRAMEWORK_DIRS=("${BUILD_PRODUCT_DIRS[@]}")
for dir in "${FRAMEWORK_DIRS[@]}"; do
  shopt -s nullglob
  frameworks=("${dir}/"*.framework)
  shopt -u nullglob
  for framework in "${frameworks[@]}"; do
    copy_bundle "$framework" "$APP/Contents/Frameworks/$(basename "$framework")"
    copied_frameworks=1
  done
done

if sparkle_framework=$(find_sparkle_framework); then
  sparkle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$sparkle_framework/Resources/Info.plist")
  [[ "$sparkle_version" == "2.9.1" ]] || fail "Expected Sparkle 2.9.1 to match the bundled notices, found $sparkle_version."
  copy_bundle "$sparkle_framework" "$APP/Contents/Frameworks/Sparkle.framework"
  copied_frameworks=1
else
  fail "Sparkle.framework was not found in the artifact used by this build."
fi

if [[ "$copied_frameworks" -eq 1 ]]; then
  chmod -R a+rX "$APP/Contents/Frameworks"
fi

if [[ -f "$ICON_TARGET" ]]; then
  cp "$ICON_TARGET" "$APP/Contents/Resources/Icon.icns"
fi

# Ensure contents are writable before stripping attributes and signing.
chmod -R u+w "$APP"

# Strip extended attributes to prevent AppleDouble files that break code sealing.
xattr -cr "$APP"
find "$APP" -name '._*' -delete

if [[ "$SIGNING_MODE" == "none" ]]; then
  CODESIGN_ARGS=()
elif [[ "$SIGNING_MODE" == "adhoc" || -z "$APP_IDENTITY" ]]; then
  CODESIGN_ARGS=(--force --sign "-")
else
  CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$APP_IDENTITY")
fi

# Sign embedded frameworks and their nested binaries before the app bundle.
sign_frameworks() {
  local fw
  for fw in "$APP/Contents/Frameworks/"*.framework; do
    if [[ ! -d "$fw" ]]; then
      continue
    fi

    while IFS= read -r -d '' nested_bundle; do
      codesign "${CODESIGN_ARGS[@]}" "$nested_bundle"
    done < <(find "$fw" -type d \( -name '*.app' -o -name '*.xpc' -o -name '*.appex' \) -print0)

    while IFS= read -r -d '' autoupdate_binary; do
      codesign "${CODESIGN_ARGS[@]}" "$autoupdate_binary"
    done < <(find "$fw" -type f -name 'Autoupdate' -perm -111 -print0)

    codesign "${CODESIGN_ARGS[@]}" "$fw"
  done
}

if [[ "$SIGNING_MODE" != "none" ]]; then
  sign_frameworks

  codesign "${CODESIGN_ARGS[@]}" \
    --entitlements "$APP_ENTITLEMENTS" \
    "$APP"

  SIGNED_ENTITLEMENTS=$(mktemp "${TMPDIR:-/tmp}/appwink-entitlements.XXXXXX")
  trap 'rm -f "$SIGNED_ENTITLEMENTS"' EXIT
  if ! codesign -d --entitlements :- "$APP" > "$SIGNED_ENTITLEMENTS" 2>/dev/null; then
    fail "Could not read signed entitlements from $APP."
  fi

  assert_signed_entitlement_absent "$SIGNED_ENTITLEMENTS" "com.apple.security.automation.apple-events"
  assert_signed_entitlement_absent "$SIGNED_ENTITLEMENTS" "com.apple.security.temporary-exception.apple-events"

  rm -f "$SIGNED_ENTITLEMENTS"
  trap - EXIT
fi

echo "Created $APP"
