#!/bin/sh
# Check for new OPNsense stable releases and decide next action.
# Writes GITHUB_OUTPUT lines: action, new_version, freebsd, release_url
# Usage: sh scripts/check-opnsense-release.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPAT="${ROOT}/compat.yaml"
OUR_REPO="${GITHUB_REPOSITORY:-nesvet/opnsense-curl-http3}"

gh_out() {
	_key="$1"
	_val="$2"
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		printf '%s=%s\n' "$_key" "$_val" >> "$GITHUB_OUTPUT"
	else
		printf '%s=%s\n' "$_key" "$_val"
	fi
}

compat_freebsd() {
	_ver="$1"
	awk -v v="$_ver" '
		$0 ~ "^  \"" v "\"":$" { in_line=1; next }
		in_line && /freebsd:/ {
			gsub(/.*freebsd:[[:space:]]*/, "")
			gsub(/"/, "")
			print
			exit
		}
	' "$COMPAT"
}

latest_opnsense_stable() {
	_python="$(command -v python3 || command -v python || true)"
	[ -n "$_python" ] || {
		echo "error: python3 required" >&2
		exit 1
	}
	"$_python" <<'PY'
import json
import re
import urllib.request

url = "https://api.github.com/repos/opnsense/core/releases?per_page=30"
req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
with urllib.request.urlopen(req, timeout=30) as resp:
    releases = json.load(resp)

pat = re.compile(r"^(\d+\.\d+)$")
for rel in releases:
    tag = (rel.get("tag_name") or "").lstrip("v")
    if pat.match(tag) and not rel.get("prerelease"):
        print(tag)
        print(rel.get("html_url") or "")
        break
PY
}

tag_exists() {
	_tag="$1"
	if command -v gh >/dev/null 2>&1; then
		gh api "repos/${OUR_REPO}/git/ref/tags/${_tag}" >/dev/null 2>&1 && return 0
	fi
	_code="$(curl -fsSL -o /dev/null -w '%{http_code}' "https://api.github.com/repos/${OUR_REPO}/git/ref/tags/${_tag}" 2>/dev/null || printf '404')"
	[ "$_code" = "200" ]
}

open_opnsense_pr() {
	if ! command -v gh >/dev/null 2>&1; then
		return 1
	fi
	gh pr list --repo "$OUR_REPO" --state open --json headRefName \
		--jq '.[].headRefName' | grep -q '^opnsense/'
}

[ -f "$COMPAT" ] || {
	echo "error: compat.yaml not found" >&2
	exit 1
}

_read="$(latest_opnsense_stable)" || true
NEW_VERSION="$(printf '%s' "$_read" | sed -n '1p')"
RELEASE_URL="$(printf '%s' "$_read" | sed -n '2p')"

if [ -z "$NEW_VERSION" ]; then
	gh_out action none
	gh_out new_version ""
	gh_out freebsd ""
	gh_out release_url ""
	exit 0
fi

if tag_exists "$NEW_VERSION"; then
	gh_out action none
	gh_out new_version "$NEW_VERSION"
	gh_out freebsd ""
	gh_out release_url "$RELEASE_URL"
	exit 0
fi

if open_opnsense_pr; then
	gh_out action none
	gh_out new_version "$NEW_VERSION"
	gh_out freebsd ""
	gh_out release_url "$RELEASE_URL"
	exit 0
fi

FREEBSD="$(compat_freebsd "$NEW_VERSION")"
if [ -z "$FREEBSD" ]; then
	gh_out action issue
	gh_out new_version "$NEW_VERSION"
	gh_out freebsd ""
	gh_out release_url "$RELEASE_URL"
	exit 0
fi

gh_out action pr
gh_out new_version "$NEW_VERSION"
gh_out freebsd "$FREEBSD"
gh_out release_url "$RELEASE_URL"
