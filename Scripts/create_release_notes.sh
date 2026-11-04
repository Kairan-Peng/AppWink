#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

TEMPLATE_PATH=${TEMPLATE_PATH:-"$ROOT_DIR/docs/releases/TEMPLATE.md"}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT_DIR/docs/releases"}
VERSION=${VERSION:-}
OVERWRITE=${OVERWRITE:-0}
STDOUT_ONLY=${STDOUT_ONLY:-0}

if [[ -f "$ROOT_DIR/version.env" ]]; then
  source "$ROOT_DIR/version.env"
fi

DEFAULT_VERSION=${MARKETING_VERSION:-0.1.0}
VERSION=${VERSION:-$DEFAULT_VERSION}

usage() {
  cat <<EOF
Usage: $(basename "$0") [--version X.Y.Z] [--output-dir PATH] [--template PATH] [--overwrite] [--stdout]

Create a repository-tracked release note from docs/releases/TEMPLATE.md.

Options:
  --version X.Y.Z        Release version. Defaults to version.env MARKETING_VERSION.
  --output-dir PATH      Output directory. Default: ${OUTPUT_DIR}
  --template PATH        Template path. Default: ${TEMPLATE_PATH}
  --overwrite            Overwrite an existing release note.
  --stdout               Print the generated note to stdout instead of writing a file.
  --help                 Show this help.

Environment:
  VERSION                Same as --version.
  OUTPUT_DIR             Same as --output-dir.
  TEMPLATE_PATH          Same as --template.
  OVERWRITE=1            Same as --overwrite.
  STDOUT_ONLY=1          Same as --stdout.

Examples:
  ./Scripts/create_release_notes.sh --version 0.1.11
  ./Scripts/create_release_notes.sh --version 0.1.11 --stdout
EOF
}

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --template)
      TEMPLATE_PATH="$2"
      shift 2
      ;;
    --overwrite)
      OVERWRITE=1
      shift
      ;;
    --stdout)
      STDOUT_ONLY=1
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

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  fail "Template not found at $TEMPLATE_PATH"
fi

OUTPUT_PATH="$OUTPUT_DIR/v${VERSION}.md"

CONTENT="$(sed "s/__VERSION__/${VERSION}/g" "$TEMPLATE_PATH")"

if [[ "$STDOUT_ONLY" == "1" ]]; then
  printf '%s\n' "$CONTENT"
  exit 0
fi

mkdir -p "$OUTPUT_DIR"

if [[ -f "$OUTPUT_PATH" && "$OVERWRITE" != "1" ]]; then
  fail "Release note already exists at $OUTPUT_PATH. Use --overwrite to replace it."
fi

printf '%s\n' "$CONTENT" > "$OUTPUT_PATH"
log "Created $OUTPUT_PATH"
