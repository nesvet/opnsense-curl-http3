## curl-http3 {{TAG}}

Pre-built HTTP/3 `curl` sidecar for **OPNsense {{OPNSENSE}}** on FreeBSD **{{FREEBSD}}** (quiche **{{QUICHE}}**, curl **{{CURL}}**).

System `/usr/local/bin/curl` is **not** replaced.

### Install (one-liner)

```sh
{{INSTALL_ONELINER}}
```

Or manual: download `curl-http3-{{TAG}}-{amd64,arm64}.tgz` below and run `scripts/install.sh`.

### SHA256

```
{{SHA256SUMS}}
```

### Verify

```sh
curl-http3 --version
curl-http3 --http3-only -I --max-time 10 https://cloudflare.com
```

Wrapper: `/usr/local/bin/curl-http3` (sets `LD_LIBRARY_PATH` automatically).
