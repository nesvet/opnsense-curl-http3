#!/bin/sh
# Install curl-http3 on OPNsense / FreeBSD.
# Usage: sudo sh install.sh /path/to/curl-http3-<opnsense>-<arch>.tgz
set -e

PREFIX="${INSTALL_PREFIX:-/opt/curl-http3}"
WRAPPER_BIN="${WRAPPER_BIN:-/usr/local/bin/curl-http3}"
INSTALL_WRAPPER="${INSTALL_WRAPPER:-1}"
TARBALL="${1:-}"

usage() {
	echo "usage: sudo sh install.sh /path/to/curl-http3-<opnsense>-<arch>.tgz" >&2
	echo "       INSTALL_PREFIX=/opt/curl-http3 (default)" >&2
	echo "       WRAPPER_BIN=/usr/local/bin/curl-http3 (default)" >&2
	echo "       INSTALL_WRAPPER=0 to skip wrapper" >&2
	exit 1
}

[ -n "$TARBALL" ] && [ -f "$TARBALL" ] || usage
[ "$(id -u)" -eq 0 ] || {
	echo "error: run as root (sudo)" >&2
	exit 1
}

STAGE="/tmp/curl-http3-install.$$"
cleanup() {
	rm -rf "$STAGE"
	case "$TARBALL" in
		/tmp/*) rm -f "$TARBALL" ;;
	esac
}
trap cleanup EXIT

echo "==> extracting ${TARBALL}"
mkdir -p "$STAGE"
tar -xzf "$TARBALL" -C "$STAGE"

[ -f "${STAGE}/MANIFEST.json" ] || {
	echo "error: MANIFEST.json missing in tarball" >&2
	exit 1
}

verify_checksums() {
	echo "==> verifying checksums"
	_python="$(command -v python3 || command -v python || true)"
	[ -n "$_python" ] || {
		echo "error: python3 required for checksum verify" >&2
		exit 1
	}
	"$_python" - "$STAGE" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

stage = Path(sys.argv[1])
manifest = json.loads((stage / "MANIFEST.json").read_text())
files = manifest.get("files") or {}
for rel, expected in files.items():
	path = stage / rel
	if not path.is_file():
		raise SystemExit(f"missing file: {rel}")
	digest = hashlib.sha256(path.read_bytes()).hexdigest()
	if digest != expected:
		raise SystemExit(f"checksum mismatch: {rel}")
print(f"verified {len(files)} file(s)")
PY
}

install_files() {
	_bin=""
	for _candidate in "${STAGE}/bin/"*; do
		[ -f "$_candidate" ] || continue
		_bin="$(basename "$_candidate")"
		break
	done
	[ -n "$_bin" ] || {
		echo "error: no binary in tarball bin/" >&2
		exit 1
	}

	echo "==> installing to ${PREFIX}" >&2
	install -d "${PREFIX}/bin" "${PREFIX}/lib"
	install -m 755 "${STAGE}/bin/${_bin}" "${PREFIX}/bin/${_bin}"
	for _lib in "${STAGE}/lib/"*.so*; do
		[ -e "$_lib" ] || continue
		install -m 755 "$_lib" "${PREFIX}/lib/"
	done
	printf '%s' "$_bin"
}

install_wrapper() {
	_bin="$1"
	[ "$INSTALL_WRAPPER" = "1" ] || return 0
	echo "==> installing wrapper ${WRAPPER_BIN}" >&2
	_tmp="${WRAPPER_BIN}.$$"
	cat > "$_tmp" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH="${PREFIX}/lib"
exec "${PREFIX}/bin/${_bin}" "\$@"
EOF
	chmod 755 "$_tmp"
	install -m 755 "$_tmp" "${WRAPPER_BIN}"
	rm -f "$_tmp"
}

smoke_binary() {
	_label="$1"
	_curl="$2"
	echo "==> smoke (${_label}): version"
	"$_curl" --version
	"$_curl" --version | grep -qi http3 || {
		echo "error: HTTP3 not in curl --version (${_label})" >&2
		exit 1
	}
	echo "==> smoke (${_label}): http3-only probe"
	"$_curl" --http3-only -I --max-time 10 https://cloudflare.com | head -5
}

smoke() {
	_bin="$1"
	_direct="${PREFIX}/bin/${_bin}"
	export LD_LIBRARY_PATH="${PREFIX}/lib"
	smoke_binary "binary" "$_direct"
	if [ "$INSTALL_WRAPPER" = "1" ] && [ -x "${WRAPPER_BIN}" ]; then
		smoke_binary "wrapper" "${WRAPPER_BIN}"
	fi
}

verify_checksums
_BIN_NAME="$(install_files)"
install_wrapper "$_BIN_NAME"
smoke "$_BIN_NAME"
if [ "$INSTALL_WRAPPER" = "1" ]; then
	echo "OK: ${WRAPPER_BIN} (wrapper) + ${PREFIX}/bin/${_BIN_NAME}"
else
	echo "OK: ${PREFIX}/bin/${_BIN_NAME}"
fi
