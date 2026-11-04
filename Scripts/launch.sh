#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_EXECUTABLE_NAME=${APP_EXECUTABLE_NAME:-${APP_NAME:-AppWink}}
APP_DISPLAY_NAME=${APP_DISPLAY_NAME:-AppWink}
APP_BUNDLE_NAME=${APP_BUNDLE_NAME:-$APP_DISPLAY_NAME}
APP_PATH="$PROJECT_ROOT/${APP_BUNDLE_NAME}.app"

echo "==> Killing existing ${APP_DISPLAY_NAME} instances"
pkill -x "$APP_EXECUTABLE_NAME" || pkill -f "${APP_BUNDLE_NAME}.app" || true
sleep 0.5

if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: ${APP_BUNDLE_NAME}.app not found at $APP_PATH"
    echo "Run ./Scripts/package_app.sh first to build the app"
    exit 1
fi

echo "==> Launching ${APP_DISPLAY_NAME} from $APP_PATH"
open -n "$APP_PATH"

sleep 1
if pgrep -x "$APP_EXECUTABLE_NAME" > /dev/null; then
    echo "OK: ${APP_DISPLAY_NAME} is running."
else
    echo "ERROR: App exited immediately. Check crash logs in Console.app (User Reports)."
    exit 1
fi
