# Collectors Catalog (MVP)

Enabled by default:

- mvp-01-device-info
- mvp-02-environment
- mvp-03-storage
- mvp-04-proc-snapshot
- mvp-05-dmesg
- mvp-06-network-basics
- mvp-07-routes-rules
- mvp-08-sockets-ports
- mvp-09-keenetic-config (best-effort)
- mvp-10-ndm-events-hooks (best-effort)
- mvp-11-entware-opkg (best-effort)
- mvp-12-entware-services (best-effort)
- mvp-13-web-discovery (gated by network policy; disabled in light by default)
- mvp-14-sensitive-scan
- mvp-16-summary
- mvp-18-diff (if baseline exists)
- mvp-17-checksums

Disabled by default:

- mvp-15-mirror (heavy)

Each collector writes artifacts under its category folder and a result JSON under `logs/collectors/<id>/`.
