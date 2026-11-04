#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

APP_BUNDLE_NAME=${APP_BUNDLE_NAME:-${APP_NAME:-AppWink}}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT_DIR/dist/release-notes"}
VERSION=${VERSION:-}
ARCHIVE_NAME=${ARCHIVE_NAME:-}
INPUT_PATH=${INPUT_PATH:-}
STDOUT_ONLY=${STDOUT_ONLY:-0}

if [[ -f "$ROOT_DIR/version.env" ]]; then
  source "$ROOT_DIR/version.env"
fi

DEFAULT_VERSION=${MARKETING_VERSION:-0.1.0}
DEFAULT_BUILD_NUMBER=${BUILD_NUMBER:-1}
VERSION=${VERSION:-$DEFAULT_VERSION}
ARCHIVE_NAME=${ARCHIVE_NAME:-"${APP_BUNDLE_NAME}-v${VERSION}-build${DEFAULT_BUILD_NUMBER}-mac"}
INPUT_PATH=${INPUT_PATH:-"$ROOT_DIR/docs/releases/v${VERSION}.md"}

usage() {
  cat <<EOF
Usage: $(basename "$0") [--version X.Y.Z] [--archive-name NAME] [--input PATH] [--output-dir PATH] [--stdout]

Export a repo-tracked markdown release note into a Sparkle-friendly HTML file.

Options:
  --version X.Y.Z        Release version. Defaults to version.env MARKETING_VERSION.
  --archive-name NAME    Basename used for the output HTML file. Defaults to ${ARCHIVE_NAME}.
  --input PATH           Markdown release note source. Defaults to docs/releases/v<version>.md.
  --output-dir PATH      Output directory. Default: ${OUTPUT_DIR}
  --stdout               Print generated HTML to stdout instead of writing a file.
  --help                 Show this help.
EOF
}

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '%s\n' "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --archive-name)
      ARCHIVE_NAME="$2"
      shift 2
      ;;
    --input)
      INPUT_PATH="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
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

if [[ ! -f "$INPUT_PATH" ]]; then
  fail "Release note markdown not found at $INPUT_PATH"
fi

OUTPUT_PATH="$OUTPUT_DIR/${ARCHIVE_NAME}.html"
TITLE="${APP_BUNDLE_NAME} ${VERSION} Release Notes"
BODY_HTML_FILE=$(mktemp)
MARKDOWN_INPUT_PATH="$INPUT_PATH" /usr/bin/swift - <<'SWIFT' > "$BODY_HTML_FILE"
import Foundation

let environment = ProcessInfo.processInfo.environment
let inputPath = environment["MARKDOWN_INPUT_PATH"] ?? ""
let markdown = try String(contentsOfFile: inputPath, encoding: .utf8)

struct Renderer {
    private(set) var htmlLines: [String] = []
    private var paragraphLines: [String] = []
    private var listItems: [String] = []
    private var listTag: String?
    private var codeLines: [String] = []
    private var inCodeBlock = false

    mutating func render(_ markdown: String) {
        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            process(rawLine)
        }
        flushAll()
    }

    private mutating func process(_ rawLine: String) {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("```") {
            flushParagraph()
            flushList()

            if inCodeBlock {
                let body = codeLines.joined(separator: "\n")
                htmlLines.append("<pre><code>\(escapeHTML(body))</code></pre>")
                codeLines.removeAll()
                inCodeBlock = false
            } else {
                inCodeBlock = true
            }
            return
        }

        if inCodeBlock {
            codeLines.append(rawLine)
            return
        }

        if trimmed.isEmpty {
            flushParagraph()
            flushList()
            return
        }

        if rawLine.first?.isWhitespace == true,
           listTag != nil,
           !listItems.isEmpty {
            appendListContinuation(trimmed)
            return
        }

        if let heading = parseHeading(trimmed) {
            flushParagraph()
            flushList()
            htmlLines.append("<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>")
            return
        }

        if let listItem = parseListItem(trimmed) {
            flushParagraph()
            appendListItem(text: listItem.text, tag: listItem.tag)
            return
        }

        paragraphLines.append(trimmed)
    }

    private mutating func appendListItem(text: String, tag: String) {
        if listTag != tag {
            flushList()
            listTag = tag
        }
        listItems.append("<li>\(renderInline(text))</li>")
    }

    private mutating func appendListContinuation(_ text: String) {
        let closingTag = "</li>"
        let lastIndex = listItems.index(before: listItems.endIndex)
        guard listItems[lastIndex].hasSuffix(closingTag) else { return }
        listItems[lastIndex].removeLast(closingTag.count)
        listItems[lastIndex].append(" \(renderInline(text))\(closingTag)")
    }

    private mutating func flushParagraph() {
        guard !paragraphLines.isEmpty else { return }
        htmlLines.append("<p>\(renderInline(paragraphLines.joined(separator: " ")))</p>")
        paragraphLines.removeAll()
    }

    private mutating func flushList() {
        guard let listTag, !listItems.isEmpty else { return }
        htmlLines.append("<\(listTag)>\(listItems.joined())</\(listTag)>")
        self.listTag = nil
        listItems.removeAll()
    }

    private mutating func flushAll() {
        if inCodeBlock {
            let body = codeLines.joined(separator: "\n")
            htmlLines.append("<pre><code>\(escapeHTML(body))</code></pre>")
            codeLines.removeAll()
            inCodeBlock = false
        }
        flushParagraph()
        flushList()
    }

    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else {
            return nil
        }
        return (level, String(line.dropFirst(level + 1)))
    }

    private func parseListItem(_ line: String) -> (tag: String, text: String)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return ("ul", String(line.dropFirst(2)))
        }

        let components = line.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        if components.count == 2,
           Int(components[0]) != nil,
           components[1].first == " " {
            return ("ol", String(components[1].dropFirst()))
        }

        return nil
    }

    private func renderInline(_ text: String) -> String {
        var rendered = escapeHTML(text)
        rendered = replace(pattern: #"`([^`]+)`"#, in: rendered, template: "<code>$1</code>")
        rendered = replace(pattern: #"(?<!\*)\*\*([^*]+)\*\*"#, in: rendered, template: "<strong>$1</strong>")
        rendered = replace(pattern: #"(?<!\*)\*([^*]+)\*"#, in: rendered, template: "<em>$1</em>")
        rendered = replace(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#, in: rendered, template: "<a href=\"$2\">$1</a>")
        return rendered
    }

    private func replace(pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

var renderer = Renderer()
renderer.render(markdown)
print(renderer.htmlLines.joined(separator: "\n"))
SWIFT
BODY_HTML=$(cat "$BODY_HTML_FILE")
rm -f "$BODY_HTML_FILE"

HTML_CONTENT=$(cat <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${TITLE}</title>
  <style>
    :root { color-scheme: light dark; }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #f5f5f7;
      color: #111827;
    }
    main {
      max-width: 840px;
      margin: 0 auto;
      padding: 40px 24px 56px;
    }
    h1 {
      margin: 0 0 20px;
      font-size: 28px;
      line-height: 1.2;
    }
    h2, h3, h4, h5, h6 {
      margin: 28px 0 12px;
      line-height: 1.25;
    }
    p, li {
      font-size: 15px;
      line-height: 1.7;
    }
    p, ul, ol, pre {
      margin: 0;
    }
    p + p, p + ul, p + ol, ul + p, ol + p, h2 + p, h3 + p, h2 + ul, h3 + ul, h2 + ol, h3 + ol, pre + p, p + pre {
      margin-top: 14px;
    }
    ul, ol {
      padding-left: 24px;
    }
    code {
      padding: 0.15em 0.35em;
      border-radius: 6px;
      background: rgba(15, 23, 42, 0.08);
      font: 0.92em ui-monospace, SFMono-Regular, Menlo, monospace;
    }
    pre {
      padding: 20px;
      border-radius: 18px;
      background: #ffffff;
      box-shadow: 0 10px 30px rgba(15, 23, 42, 0.08);
      overflow-x: auto;
    }
    pre code {
      padding: 0;
      background: transparent;
      border-radius: 0;
      font: 14px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace;
    }
    a {
      color: #2563eb;
      text-decoration: none;
    }
    a:hover {
      text-decoration: underline;
    }
    @media (prefers-color-scheme: dark) {
      body { background: #0f172a; color: #e5e7eb; }
      code { background: rgba(148, 163, 184, 0.16); }
      pre {
        background: #111827;
        box-shadow: none;
      }
      a { color: #93c5fd; }
    }
  </style>
</head>
<body>
  <main>
    ${BODY_HTML}
  </main>
</body>
</html>
EOF
)

if [[ "$STDOUT_ONLY" == "1" ]]; then
  printf '%s\n' "$HTML_CONTENT"
  exit 0
fi

mkdir -p "$OUTPUT_DIR"
printf '%s\n' "$HTML_CONTENT" > "$OUTPUT_PATH"
log "Created $OUTPUT_PATH"
