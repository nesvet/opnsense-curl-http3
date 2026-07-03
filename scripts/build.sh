#!/bin/sh
# Build curl-http3 for OPNsense (FreeBSD, quiche backend). amd64 + arm64.
# Run from project root: sh scripts/build.sh
# Optional: TARGET_ARCH=arm64|amd64
set -e

if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
	set -x
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="${ROOT}/lock.yaml"
CACHE="${ROOT}/.cache"
SRC="${CACHE}/src"
DIST="${ROOT}/dist"
STAGING="${ROOT}/.build/staging"

export CARGO_HOME="${CACHE}/cargo"
export CARGO_INCREMENTAL=0
export CCACHE_DIR="${CACHE}/ccache"
export CCACHE_MAXSIZE=500M
export CCACHE_COMPRESS=true
export CC="ccache cc"
export CXX="ccache c++"

lock_after() {
	_section="$1"
	_key="$2"
	awk -v section="$_section" -v key="$_key" '
		$0 ~ "^" section ":$" { in_section=1; next }
		/^[a-zA-Z0-9_]+:/ && in_section { exit }
		in_section && $1 == (key ":") { gsub(/^[^:]*:[[:space:]]*/, ""); gsub(/"/, ""); print; exit }
	' "$LOCK"
}

lock_top() {
	_key="$1"
	awk -v key="$_key" '
		$1 == (key ":") { gsub(/^[^:]*:[[:space:]]*/, ""); gsub(/"/, ""); print; exit }
	' "$LOCK"
}

# Map host/CI arch names to canonical amd64 | aarch64.
# FreeBSD reports arm64 (not aarch64) on AArch64; tarball suffix uses arm64 via package_arch_name.
normalize_arch() {
	case "$1" in
		amd64)
			printf 'amd64'
			;;
		aarch64|arm64)
			printf 'aarch64'
			;;
		'')
			echo "error: empty arch" >&2
			exit 1
			;;
		*)
			echo "error: unsupported arch ${1} (want amd64 or arm64)" >&2
			exit 1
			;;
	esac
}

# Tarball / release artifact suffix (arm64 not aarch64).
package_arch_name() {
	case "$1" in
		amd64)
			printf 'amd64'
			;;
		aarch64)
			printf 'arm64'
			;;
		*)
			echo "error: internal arch ${1} cannot be packaged" >&2
			exit 1
			;;
	esac
}

load_lock() {
	OPNSENSE="$(lock_top opnsense)"
	INSTALL_PREFIX="$(lock_after install prefix)"
	INSTALL_BIN="$(lock_after install bin)"
	INSTALL_BIN="${INSTALL_BIN:-curl-http3}"
	RPATH="${INSTALL_PREFIX}/lib"
	_machine="$(normalize_arch "${TARGET_ARCH:-$(uname -m)}")"
	PACKAGE_ARCH="$(package_arch_name "$_machine")"
	TARBALL="${ROOT}/curl-http3-${OPNSENSE}-${PACKAGE_ARCH}.tgz"
}

init_cache() {
	mkdir -p "${CACHE}/cargo" "${CACHE}/ccache" "${CACHE}/src" "${CACHE}/target" "${ROOT}/.build"
}

assert_target() {
	_host_raw="$(uname -m)"
	_host="$(normalize_arch "$_host_raw")"
	_ver="$(freebsd-version 2>/dev/null || true)"
	_want="$(lock_after target release)"
	_want_arch="$(normalize_arch "${TARGET_ARCH:-$_host_raw}")"

	echo "target: opnsense=${OPNSENSE} arch=${_host_raw} package=${PACKAGE_ARCH} freebsd=${_ver} want=${_want}"

	if [ "$_want_arch" != "$_host" ]; then
		echo "error: TARGET_ARCH=${TARGET_ARCH:-${_host_raw}} (package ${PACKAGE_ARCH}) does not match host ${_host_raw} (${_host})" >&2
		exit 1
	fi

	case "$_ver" in
		"${_want}"*)
			;;
		*)
			echo "error: expected FreeBSD ${_want}, got ${_ver:-unknown}" >&2
			exit 1
			;;
	esac
}

install_deps() {
	echo "==> installing build dependencies"
	env ASSUME_ALWAYS_YES=YES pkg update
	env ASSUME_ALWAYS_YES=YES pkg install -y \
		git gmake cmake pkgconf python3 rust llvm perl5 ca_root_nss \
		autoconf automake libtool ccache
	ccache --set-config=cache_dir="${CCACHE_DIR}"
	ccache --set-config=max_size="${CCACHE_MAXSIZE}"
	ccache --set-config=compression=true
}

ensure_repo() {
	_name="$1"
	_repo="$2"
	_tag="$3"
	_dir="${SRC}/${_name}"
	_stamp="${SRC}/${_name}.tag"

	mkdir -p "${SRC}"
	if [ -d "${_dir}/.git" ]; then
		echo "==> reuse ${_name} clone"
		cd "${_dir}"
		if [ -f "$_stamp" ] && [ "$(cat "$_stamp")" = "$_tag" ]; then
			return 0
		fi
		git fetch --depth 1 origin "refs/tags/${_tag}:refs/tags/${_tag}" 2>/dev/null \
			|| git fetch origin tag "${_tag}"
		git checkout -f "${_tag}"
		git submodule update --init --recursive
	else
		echo "==> clone ${_name} ${_tag}"
		rm -rf "${_dir}"
		git clone --depth 1 --branch "${_tag}" --recursive "${_repo}" "${_dir}"
	fi
	printf '%s' "${_tag}" > "${_stamp}"
}

setup_quiche_boringssl() {
	_quiche="${SRC}/quiche"
	_out="${CARGO_TARGET_DIR}/release"
	cd "${_quiche}"
	ln -sf libquiche.so "${_out}/libquiche.so.0"
	mkdir -p boringssl/lib
	find "${_out}" \( -name libcrypto.a -o -name libssl.a \) -exec ln -vnf -- '{}' boringssl/lib \;
	_include="$(find "${_out}"/build/boring-sys-*/out/boringssl/src -maxdepth 1 -name include -print 2>/dev/null | head -1)"
	[ -n "$_include" ] && [ -d "$_include" ] || {
		echo "error: boringssl include dir not found" >&2
		exit 1
	}
	_abs_include="$(cd "$_include" && pwd -P)"
	ln -vsfn "$_abs_include" boringssl/include
	[ -e boringssl/include/openssl/ssl.h ] || {
		echo "error: openssl headers not found under boringssl/include" >&2
		exit 1
	}
}

build_quiche() {
	_tag="$(lock_after quiche tag)"
	_repo="$(lock_after quiche repo)"

	echo "==> quiche ${_tag}"
	ensure_repo quiche "$_repo" "$_tag"
	export CARGO_TARGET_DIR="${CACHE}/target/quiche"
	cd "${SRC}/quiche"
	cargo build --package quiche --release --features ffi,pkg-config-meta,qlog
	setup_quiche_boringssl
}

build_curl() {
	_tag="$(lock_after curl tag)"
	_repo="$(lock_after curl repo)"

	echo "==> curl ${_tag}"
	ensure_repo curl "$_repo" "$_tag"
	cd "${SRC}/curl"
	autoreconf -fi
	QUICHE_DIR="${SRC}/quiche"
	_quiche_out="${CARGO_TARGET_DIR}/release"
	export PKG_CONFIG_PATH="${_quiche_out}:${PKG_CONFIG_PATH:-}"
	./configure \
		--prefix="${STAGING}" \
		--with-openssl="${QUICHE_DIR}/boringssl" \
		--with-quiche="${_quiche_out}" \
		LDFLAGS="-Wl,-rpath,${RPATH} -L${_quiche_out}" \
		CPPFLAGS="-I${QUICHE_DIR}/boringssl/include" || {
			echo "error: curl configure failed" >&2
			tail -50 config.log 2>/dev/null || true
			exit 1
		}
	gmake -j"$(sysctl -n hw.ncpu)"
	gmake install
	install -d "${DIST}/bin" "${DIST}/lib"
	install -m 755 "${STAGING}/bin/curl" "${DIST}/bin/${INSTALL_BIN}"
}

collect_libs() {
	_curl="${DIST}/bin/${INSTALL_BIN}"

	echo "==> collecting shared libraries"
	_ldd="$(ldd "$_curl" 2>/dev/null || true)"
	echo "$_ldd"

	for _lib in $(echo "$_ldd" | awk '/=>/ {print $3}' | grep -v '^$'); do
		case "$_lib" in
			/lib/*|/usr/lib/*) continue ;;
		esac
		[ -f "$_lib" ] || continue
		install -m 755 "$_lib" "${DIST}/lib/"
	done

	_quiche_so="${CARGO_TARGET_DIR}/release/libquiche.so"
	if [ -f "$_quiche_so" ]; then
		install -m 755 "$_quiche_so" "${DIST}/lib/"
		ln -sf libquiche.so "${DIST}/lib/libquiche.so.0"
	fi
}

smoke() {
	_curl="${DIST}/bin/${INSTALL_BIN}"
	export LD_LIBRARY_PATH="${DIST}/lib"

	echo "==> smoke: version"
	"$_curl" --version
	"$_curl" --version | grep -qi http3 || {
		echo "error: HTTP3 not in curl --version" >&2
		exit 1
	}

	echo "==> smoke: http3-only probe"
	"$_curl" --http3-only -I --max-time 15 https://cloudflare.com >/dev/null
}

write_manifest() {
	_curl_tag="$(lock_after curl tag)"
	_quiche_tag="$(lock_after quiche tag)"
	_curl_sha="$(cd "${SRC}/curl" && git rev-parse HEAD 2>/dev/null || echo unknown)"
	_quiche_sha="$(cd "${SRC}/quiche" && git rev-parse HEAD 2>/dev/null || echo unknown)"

	echo "==> writing MANIFEST.json"
	{
		printf '{\n'
		printf '  "opnsense": "%s",\n' "$OPNSENSE"
		printf '  "target": {\n'
		printf '    "os": "freebsd",\n'
		printf '    "release": "%s",\n' "$(freebsd-version)"
		printf '    "arch": "%s"\n' "$(uname -m)"
		printf '  },\n'
		printf '  "curl": { "tag": "%s", "sha": "%s" },\n' "$_curl_tag" "$_curl_sha"
		printf '  "quiche": { "tag": "%s", "sha": "%s" },\n' "$_quiche_tag" "$_quiche_sha"
		printf '  "install": { "prefix": "%s", "bin": "%s" },\n' "$INSTALL_PREFIX" "$INSTALL_BIN"
		printf '  "files": {\n'
		_first=1
		for _f in "${DIST}/bin/${INSTALL_BIN}" "${DIST}/lib/"*.so*; do
			[ -f "$_f" ] || continue
			_rel="${_f#${DIST}/}"
			_sum="$(sha256 -q "$_f")"
			[ "$_first" -eq 1 ] || printf ',\n'
			_first=0
			printf '    "%s": "%s"' "$_rel" "$_sum"
		done
		printf '\n  }\n'
		printf '}\n'
	} > "${DIST}/MANIFEST.json"
}

package() {
	echo "==> packaging ${TARBALL}"
	rm -f "$TARBALL" "${TARBALL}.sha256"
	tar -C "${DIST}" -czf "$TARBALL" .
	sha256 -q "$TARBALL" > "${TARBALL}.sha256"
	ls -la "$TARBALL" "${TARBALL}.sha256"
}

main() {
	cd "$ROOT"
	load_lock
	assert_target
	init_cache
	rm -rf "${DIST}" "${STAGING}"
	mkdir -p "${DIST}"
	install_deps
	build_quiche
	build_curl
	collect_libs
	smoke
	write_manifest
	package
	echo "OK: ${TARBALL}"
}

main "$@"
