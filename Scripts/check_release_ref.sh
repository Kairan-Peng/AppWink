#!/usr/bin/env bash
set -euo pipefail

# Run this trusted-main helper before checking out any requested release source.
# The caller must have fetched origin/main and tags without persisted credentials.
python3 - "$@" <<'PY'
import re
import subprocess
import sys


def fail(message):
    raise SystemExit(f"ERROR: {message}")


def git(*args):
    result = subprocess.run(["git", *args], capture_output=True, text=True)
    if result.returncode:
        fail("Git validation failed; expected an existing commit/ref on origin/main.")
    return result.stdout.strip()


def require_main_ancestor(commit):
    if subprocess.run(
        ["git", "merge-base", "--is-ancestor", commit, "refs/remotes/origin/main"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode:
        fail("Release source must be reachable from origin/main.")


if not 1 <= len(sys.argv[1:]) <= 2:
    fail("Usage: check_release_ref.sh TAG [main|TAG|FULL_COMMIT_SHA]")

tag = sys.argv[1]
requested_ref = sys.argv[2] if len(sys.argv) == 3 else ""
semver = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
if not re.fullmatch("v" + semver, tag):
    fail("Expected a canonical semantic version tag such as v0.1.44.")

tag_ref = f"refs/tags/{tag}"
tag_object_sha = git("rev-parse", "--verify", tag_ref)
tag_sha = git("rev-parse", "--verify", f"{tag_ref}^{{commit}}")
require_main_ancestor(tag_sha)

selected_ref = requested_ref or tag
if selected_ref == "main":
    qualified_ref = "refs/remotes/origin/main"
elif re.fullmatch("v" + semver, selected_ref):
    qualified_ref = f"refs/tags/{selected_ref}"
elif re.fullmatch(r"[0-9a-f]{40}", selected_ref):
    qualified_ref = selected_ref
else:
    fail("Checkout ref must be main, a canonical version tag, or a full lowercase commit SHA.")

source_sha = git("rev-parse", "--verify", f"{qualified_ref}^{{commit}}")
require_main_ancestor(source_sha)

# Read metadata as data, never source shell code from the requested commit.
metadata = git("show", f"{source_sha}:version.env")
values = {}
for line in metadata.splitlines():
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    match = re.fullmatch(r"(MARKETING_VERSION|BUILD_NUMBER)=([0-9.]+)", line)
    if not match or match[1] in values:
        fail("version.env must contain one literal MARKETING_VERSION and BUILD_NUMBER only.")
    values[match[1]] = match[2]
if set(values) != {"MARKETING_VERSION", "BUILD_NUMBER"}:
    fail("version.env is missing release metadata.")
version = values["MARKETING_VERSION"]
build_number = values["BUILD_NUMBER"]
if not re.fullmatch(semver, version) or version != tag[1:]:
    fail("MARKETING_VERSION must match the requested release tag.")
if not re.fullmatch(r"[1-9][0-9]*", build_number):
    fail("BUILD_NUMBER must be a positive integer without leading zeroes.")

notes_path = f"docs/releases/{tag}.md"
tree_entry = git("ls-tree", source_sha, "--", notes_path)
if not tree_entry.startswith("100644 blob ") or not git("show", f"{source_sha}:{notes_path}"):
    fail("Expected a non-empty regular release note for the selected source.")

# Explicit main/SHA replays cannot create a release, even at the tag's commit.
should_publish = not requested_ref or requested_ref == tag
for key, value in {
    "tag_name": tag,
    "tag_object_sha": tag_object_sha,
    "source_sha": source_sha,
    "version": version,
    "build_number": build_number,
    "release_basename": f"AppWink-v{version}-build{build_number}-mac",
    "release_notes_path": notes_path,
    "release_title": f"AppWink {tag}",
    "should_publish": str(should_publish).lower(),
}.items():
    print(f"{key}={value}")
PY
