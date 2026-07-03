# Security

This project distributes **pre-built binaries** built in GitHub Actions from pinned curl/quiche sources. It does not replace the system `curl` on OPNsense.

## Scope

- Sidecar binary at `/opt/curl-http3` plus optional wrapper `/usr/local/bin/curl-http3`.
- Build runs in CI on FreeBSD VMs; release artifacts are tarballs and `SHA256SUMS`.
- Install script verifies per-file checksums from `MANIFEST.json` inside each tarball.

## Verify downloads

1. Compare tarball SHA256 against `SHA256SUMS` on the [Releases](https://github.com/nesvet/opnsense-curl-http3/releases) page.
2. `install.sh` verifies `MANIFEST.json` file hashes after extract.

## Reporting

Report vulnerabilities via [GitHub Security Advisories](https://github.com/nesvet/opnsense-curl-http3/security/advisories) on this repository.

Do **not** attach binaries to public issues — provide `opnsense-version`, `freebsd-version`, `uname -m`, and `curl-http3 --version` output instead.

## Trust model

- Same tagged source + lock pins should produce reproducible builds via CI.
- Treat any modified binary as untrusted until checksums and smoke tests pass on your system.
