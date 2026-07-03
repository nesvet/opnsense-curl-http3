#!/bin/sh
# Bump lock.yaml for a new OPNsense line. Usage: sh scripts/bump-lock.sh VERSION FREEBSD
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="${ROOT}/lock.yaml"
VERSION="${1:-}"
FREEBSD="${2:-}"
TODAY="$(date +%Y-%m-%d)"

[ -n "$VERSION" ] && [ -n "$FREEBSD" ] || {
	echo "usage: sh scripts/bump-lock.sh <opnsense-version> <freebsd-release>" >&2
	exit 1
}

awk -v ver="$VERSION" -v fb="$FREEBSD" -v today="$TODAY" '
/^opnsense:/ { print "opnsense: \"" ver "\""; next }
/^  release:/ { print "  release: \"" fb "\""; next }
/^verified:/ { print "verified: " today; next }
{ print }
' "$LOCK" > "${LOCK}.tmp"
mv "${LOCK}.tmp" "$LOCK"
echo "updated lock.yaml: opnsense=${VERSION} freebsd=${FREEBSD}"
