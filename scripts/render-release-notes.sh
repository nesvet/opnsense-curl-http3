#!/bin/sh
# Render release notes from template + lock.yaml + SHA256SUMS.
# Usage: sh scripts/render-release-notes.sh [TAG] > RELEASE.md
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="${ROOT}/lock.yaml"
TEMPLATE="${ROOT}/.github/release-notes.md"
TAG="${1:-}"
SUMS="${ROOT}/SHA256SUMS"

_python="$(command -v python3 || command -v python || true)"
[ -n "$_python" ] || {
	echo "error: python3 required" >&2
	exit 1
}

"$_python" - "$LOCK" "$TEMPLATE" "$SUMS" "$TAG" <<'PY'
import sys
from pathlib import Path

lock_path, template_path, sums_path, tag_arg = sys.argv[1:5]

def lock_top(key: str) -> str:
    for line in Path(lock_path).read_text().splitlines():
        if line.startswith(f"{key}:"):
            return line.split(":", 1)[1].strip().strip('"')
    return ""

def lock_after(section: str, key: str) -> str:
    in_section = False
    for line in Path(lock_path).read_text().splitlines():
        if line.rstrip().endswith(f"{section}:"):
            in_section = True
            continue
        if in_section and line and not line.startswith(" ") and line.endswith(":"):
            break
        if in_section and line.strip().startswith(f"{key}:"):
            return line.split(":", 1)[1].strip().strip('"')
    return ""

opnsense = lock_top("opnsense")
tag = tag_arg or opnsense
freebsd = lock_after("target", "release")
curl_ver = lock_after("curl", "version")
quiche = lock_after("quiche", "tag")
sums = Path(sums_path).read_text() if Path(sums_path).is_file() else "(SHA256SUMS not generated)"
install = "fetch -o - https://raw.githubusercontent.com/nesvet/opnsense-curl-http3/main/scripts/install-remote.sh | sh"

text = Path(template_path).read_text()
text = text.replace("{{TAG}}", tag)
text = text.replace("{{OPNSENSE}}", opnsense)
text = text.replace("{{FREEBSD}}", freebsd)
text = text.replace("{{CURL}}", curl_ver)
text = text.replace("{{QUICHE}}", quiche)
text = text.replace("{{INSTALL_ONELINER}}", install)
text = text.replace("{{SHA256SUMS}}", sums.rstrip())
print(text, end="")
PY
