#!/bin/sh
# Remote install curl-http3 on OPNsense / FreeBSD from GitHub Releases.
# Usage: fetch -o - .../install-remote.sh | sh
#        sh install-remote.sh [--tag 26.1] [--arch amd64|arm64] [--repo owner/name] [--dry-run]
set -e

REPO="${REPO:-nesvet/opnsense-curl-http3}"
TAG=""
ARCH=""
DRY_RUN=0

usage() {
	echo "usage: sh install-remote.sh [options]" >&2
	echo "  --tag X.Y       release tag (default: from opnsense-version)" >&2
	echo "  --arch amd64|arm64  (default: from uname -m)" >&2
	echo "  --repo owner/name   (default: ${REPO})" >&2
	echo "  --dry-run       print URLs only" >&2
	exit 1
}

while [ $# -gt 0 ]; do
	case "$1" in
		--tag)
			[ -n "${2:-}" ] || usage
			TAG="$2"
			shift 2
			;;
		--arch)
			[ -n "${2:-}" ] || usage
			ARCH="$2"
			shift 2
			;;
		--repo)
			[ -n "${2:-}" ] || usage
			REPO="$2"
			shift 2
			;;
		--dry-run)
			DRY_RUN=1
			shift
			;;
		-h|--help)
			usage
			;;
		*)
			echo "error: unknown option: $1" >&2
			usage
			;;
	esac
done

detect_tag() {
	if [ -n "$TAG" ]; then
		return 0
	fi
	if command -v opnsense-version >/dev/null 2>&1; then
		_ver="$(opnsense-version 2>/dev/null || true)"
		_full="$(printf '%s' "$_ver" | awk '{print $2}')"
		_base="$(printf '%s' "$_full" | sed 's/_.*//')"
		TAG="$(printf '%s' "$_base" | awk -F. '{print $1"."$2}')"
	fi
	[ -n "$TAG" ] || {
		echo "error: cannot detect OPNsense version (use --tag)" >&2
		exit 1
	}
}

detect_arch() {
	if [ -n "$ARCH" ]; then
		case "$ARCH" in
			amd64|arm64) ;;
			*)
				echo "error: --arch must be amd64 or arm64" >&2
				exit 1
				;;
		esac
		return 0
	fi
	_m="$(uname -m)"
	case "$_m" in
		amd64) ARCH=amd64 ;;
		aarch64) ARCH=arm64 ;;
		*)
			echo "error: unsupported uname -m: $_m (use --arch)" >&2
			exit 1
			;;
	esac
}

base_url() {
	printf 'https://github.com/%s/releases/download/%s' "$REPO" "$TAG"
}

raw_url() {
	printf 'https://raw.githubusercontent.com/%s/main' "$REPO"
}

verify_sha256() {
	_file="$1"
	_expected="$2"
	_got="$(sha256 -q "$_file" 2>/dev/null || shasum -a 256 "$_file" | awk '{print $1}')"
	[ "$_got" = "$_expected" ] || {
		echo "error: SHA256 mismatch for $(basename "$_file")" >&2
		echo "  expected: $_expected" >&2
		echo "  got:      $_got" >&2
		exit 1
	}
}

fetch_sha256sums() {
	_sums="${TMPDIR:-/tmp}/curl-http3-SHA256SUMS.$$"
	_url="$(base_url)/SHA256SUMS"
	if ! fetch -o "$_sums" "$_url" 2>/dev/null; then
		echo "warning: SHA256SUMS not found at release (skipping verify)" >&2
		rm -f "$_sums"
		return 1
	fi
	printf '%s' "$_sums"
}

lookup_sum() {
	_sums_file="$1"
	_name="$2"
	awk -v n="$_name" '$2 == n { print $1; exit }' "$_sums_file"
}

detect_tag
detect_arch

TARBALL_NAME="curl-http3-${TAG}-${ARCH}.tgz"
TARBALL_URL="$(base_url)/${TARBALL_NAME}"
INSTALL_URL="$(raw_url)/scripts/install.sh"

echo "==> repo=${REPO} tag=${TAG} arch=${ARCH}"
echo "    tarball: ${TARBALL_URL}"
echo "    install: ${INSTALL_URL}"

if [ "$DRY_RUN" -eq 1 ]; then
	exit 0
fi

TARBALL="${TMPDIR:-/tmp}/${TARBALL_NAME}"
INSTALL_SH="${TMPDIR:-/tmp}/curl-http3-install.$$"
SUMS_FILE=""

cleanup() {
	rm -f "$INSTALL_SH"
	[ -f "$SUMS_FILE" ] && rm -f "$SUMS_FILE"
}
trap cleanup EXIT

if SUMS_FILE="$(fetch_sha256sums)"; then
	_expected="$(lookup_sum "$SUMS_FILE" "$TARBALL_NAME")"
	[ -n "$_expected" ] || {
		echo "error: ${TARBALL_NAME} not listed in SHA256SUMS" >&2
		exit 1
	}
fi

echo "==> fetching ${TARBALL_NAME}"
fetch -o "$TARBALL" "$TARBALL_URL"

if [ -n "$SUMS_FILE" ] && [ -f "$SUMS_FILE" ]; then
	echo "==> verifying SHA256"
	verify_sha256 "$TARBALL" "$_expected"
fi

echo "==> fetching install.sh"
fetch -o "$INSTALL_SH" "$INSTALL_URL"

if [ "$(id -u)" -eq 0 ]; then
	sh "$INSTALL_SH" "$TARBALL"
else
	echo "==> installing (sudo)"
	sudo sh "$INSTALL_SH" "$TARBALL"
fi
