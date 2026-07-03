# Announce draft (forum / Reddit)

**Title:** Pre-built curl with HTTP/3 for OPNsense (sidecar, no system curl replacement)

**Body:**

OPNsense ships `curl` without HTTP/3, and FreeBSD ports recently dropped HTTP/3 in `ftp/curl`. If you need `--http3-only` on the firewall itself (QUIC/DPI checks, blockcheck, CDN probes), I maintain a small project that builds a **quiche-backed curl sidecar** for OPNsense on FreeBSD amd64 and arm64.

- Does **not** replace `/usr/local/bin/curl`
- Installs to `/opt/curl-http3` + wrapper `/usr/local/bin/curl-http3`
- One-liner install from Releases

```sh
fetch -o - https://raw.githubusercontent.com/nesvet/opnsense-curl-http3/main/scripts/install-remote.sh | sh
```

Releases: https://github.com/nesvet/opnsense-curl-http3/releases

Feedback welcome via GitHub issues.
