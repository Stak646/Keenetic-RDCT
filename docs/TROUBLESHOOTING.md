# Troubleshooting

## "USB-only enforced" errors

RDCT refuses to run unless the base directory is on an external USB mount.

- Verify that your USB drive is mounted:

```sh
cat /proc/mounts | grep -E '/tmp/mnt|/media|/mnt'
```

- Use explicit `--base`:

```sh
/tmp/mnt/sda1/rdct/rdct.sh preflight
```

## Permission denied

Some collectors require root/admin access to read system state.

- Run as the router admin user (or via SSH with enough permissions)
- Switch to `medium/full` only if you need deeper collection

## Missing utilities

RDCT can optionally install missing dependencies via `opkg` (Entware) depending on configuration.

- Confirm that `/opt` is available and on USB
- Confirm that the router has network access for `opkg update`

## WebUI not reachable

- Make sure you bound to the right interface:

```sh
/tmp/mnt/sda1/rdct/rdct.sh serve --bind 0.0.0.0 --port 8080
```

- Check that the port is not in use.

## Reports are too large

- Use `light` or `medium`
- Disable mirror by default (`modes.mirror_policy.enabled=false`)
- Use export with redaction (stubs reduce size)
