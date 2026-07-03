# opnsense-curl-http3

[![build](https://github.com/nesvet/opnsense-curl-http3/actions/workflows/build.yml/badge.svg)](https://github.com/nesvet/opnsense-curl-http3/actions/workflows/build.yml)

Pre-built **`curl-http3`** for **OPNsense** on FreeBSD: `curl` with HTTP/3 (QUIC) via [quiche](https://github.com/cloudflare/quiche). Sidecar install — does not replace `/usr/local/bin/curl`.

## Problem

- OPNsense ships `curl` **without HTTP/3** (`--http3-only` fails at runtime).
- FreeBSD ports [reverted HTTP/3 support](https://github.com/FreeBSD/freebsd-ports/commit/f9ce1e48dd027339fde07bf6c33e96ceedff2f62) in `ftp/curl` (March 2026).
- There is no official pre-built package with HTTP/3 for this platform.

## Compatibility

| OPNsense | FreeBSD | amd64 | arm64 | Tag | Status |
|----------|---------|-------|-------|-----|--------|
| 26.1 | 14.3 | yes | CI | `26.1` | tested (amd64) |

Release tag = OPNsense major.minor. Pins in [`lock.yaml`](lock.yaml); FreeBSD mapping in [`compat.yaml`](compat.yaml).

## Quick start

On the firewall (root shell or `sudo`):

```sh
fetch -o - https://raw.githubusercontent.com/nesvet/opnsense-curl-http3/main/scripts/install-remote.sh | sh
```

Detects OPNsense version and architecture, verifies `SHA256SUMS`, installs to `/opt/curl-http3` and wrapper `/usr/local/bin/curl-http3`.

### Verify

```sh
curl-http3 --version
curl-http3 --http3-only -I --max-time 10 https://cloudflare.com
```

System curl should still lack HTTP/3:

```sh
curl --http3-only https://cloudflare.com
# the installed libcurl version does not support this
```

## Use cases

- **QUIC / DPI probe from the firewall** — test whether your ISP blocks HTTP/3 (not from a laptop behind NAT).
- **CDN reachability** — `--http3-only` smoke against Cloudflare, Google, etc.
- **zapret2 / blockcheck** — set `CURL=/usr/local/bin/curl-http3` and `ENABLE_HTTP3=1` ([bol-van manual](https://github.com/bol-van/zapret2/blob/master/docs/manual.en.md)).
- **Pinned IP tests** — `curl-http3 --connect-to example.com::1.2.3.4:443 --http3-only …`

See [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md).

## Install layout

| Path | Role |
|------|------|
| `/opt/curl-http3/bin/curl-http3` | HTTP/3 binary |
| `/opt/curl-http3/lib/libquiche.so*` | Runtime libraries |
| `/usr/local/bin/curl-http3` | Wrapper (sets `LD_LIBRARY_PATH`) |
| `/usr/local/bin/curl` | Unchanged |

Override prefix: `INSTALL_PREFIX=/opt/foo sh install.sh …`. Skip wrapper: `INSTALL_WRAPPER=0`.

## Manual install

[Releases](https://github.com/nesvet/opnsense-curl-http3/releases) — `curl-http3-<tag>-{amd64,arm64}.tgz` + `SHA256SUMS`.

```sh
fetch -o /tmp/curl-http3-26.1-amd64.tgz \
  https://github.com/nesvet/opnsense-curl-http3/releases/download/26.1/curl-http3-26.1-amd64.tgz
fetch -o /tmp/install.sh \
  https://raw.githubusercontent.com/nesvet/opnsense-curl-http3/main/scripts/install.sh
sh /tmp/install.sh /tmp/curl-http3-26.1-amd64.tgz
```

## New OPNsense line

When a new stable OPNsense `X.Y` ships:

1. Add a row to [`compat.yaml`](compat.yaml) with the FreeBSD base from [OPNsense releases](https://github.com/opnsense/core/releases).
2. Push to `main` — [`opnsense-watch`](.github/workflows/opnsense-watch.yml) opens a lock bump PR (or re-run workflow).
3. Merge PR after CI passes → [`tag-release`](.github/workflows/tag-release.yml) tags `X.Y` → build publishes Release.

## Rebuild

| Event | Action |
|-------|--------|
| Rebuild same line | Re-push tag or **Actions → build → Run workflow** |
| New OPNsense line | Update `compat.yaml`, merge bot PR |
| Rollback | Remove `/usr/local/bin/curl-http3` and `/opt/curl-http3/` |

## Local build (FreeBSD amd64 or arm64)

```sh
git clone https://github.com/nesvet/opnsense-curl-http3.git
cd opnsense-curl-http3
sh scripts/build.sh
```

Produces `curl-http3-<opnsense>-<arch>.tgz` in the repository root. CI: [vmactions/freebsd-vm](https://github.com/vmactions/freebsd-vm).

## Layout

```
compat.yaml
lock.yaml
scripts/build.sh
scripts/install.sh
scripts/install-remote.sh
.github/workflows/{build,opnsense-watch,tag-release}.yml
```

## Support this project

**Free, open-source, maintained by one developer.**

- **Star the repo** — discoverability
- **[Support on Patreon](https://patreon.com/nesvet)**

## License

MIT — see [LICENSE](LICENSE).
