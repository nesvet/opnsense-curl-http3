# Integrations

## zapret2 / blockcheck

OPNsense system `curl` has no HTTP/3. For QUIC probes, point blockcheck at the sidecar:

| Variable | Value |
|----------|-------|
| `CURL` | `/usr/local/bin/curl-http3` |
| `ENABLE_HTTP3` | `1` |

The wrapper sets `LD_LIBRARY_PATH` for `libquiche.so`. No need to export it manually when using `/usr/local/bin/curl-http3`.

Upstream: [bol-van/zapret2 manual — Supported protocols](https://github.com/bol-van/zapret2/blob/master/docs/manual.en.md).

### Suggested upstream doc addition (PR draft)

```markdown
### HTTP/3 on OPNsense

System curl on OPNsense/FreeBSD typically lacks HTTP/3. Install a sidecar build
(e.g. [opnsense-curl-http3](https://github.com/nesvet/opnsense-curl-http3)) and set:

    CURL=/usr/local/bin/curl-http3
    ENABLE_HTTP3=1
```

## Plain FreeBSD

Tarballs match FreeBSD `target.release` in `lock.yaml` — usable outside OPNsense on the same FreeBSD version and architecture.

## Direct binary (no wrapper)

If invoking `/opt/curl-http3/bin/curl-http3` directly:

```sh
LD_LIBRARY_PATH=/opt/curl-http3/lib /opt/curl-http3/bin/curl-http3 --http3-only …
```
