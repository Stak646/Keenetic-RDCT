# Installation / Upgrade / Uninstall

## Requirements
- Keenetic with Entware (opkg, /opt)
- python3 (installed automatically)
- Architectures: mipsel, mips, aarch64
- Free space: 10+ MB

## Online Install
```bash
curl -fsSL https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh -o /tmp/install.sh && sh /tmp/install.sh
```

The installer automatically:
1. Detects architecture and Entware
2. Installs python3 (if missing)
3. Downloads project from GitHub
4. Generates auth token
5. Creates configuration
6. Starts WebUI on free port

## Upgrade
Run installer and choose option 2 (Update).

## Uninstall
Run installer and choose option 3 (Uninstall).

## Service Management
```bash
/opt/etc/init.d/S99keeneticrdct start|stop|restart|status
```
