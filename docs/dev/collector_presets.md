# Collector Category Presets — Step 654

## Light
system.base, network.base, config.keenetic

## Medium (default)
Light + system.kernel, network.deep, network.dns_dhcp, wifi.radio, vpn.status,
storage.fs, security.exposure, config.entware, processes.extended, logs.system

## Full
Medium + storage.health, hooks.ndm, services.initd, scheduler.autostart,
logs.vpn, telemetry.mini, apps.inventory, api.search

## Extreme
Full + apps.websnap, apps.screenshot, mirror.full, config.opkg

## Override
Config `collectors.<id>.enabled = true/false` overrides presets.
