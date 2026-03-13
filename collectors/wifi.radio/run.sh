#!/bin/sh
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0

# Try iw first
if command -v iw >/dev/null 2>&1; then
  iw dev > "$ARTIFACTS/iw_dev.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  iw phy > "$ARTIFACTS/iw_phy.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  iw reg get > "$ARTIFACTS/iw_reg.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
fi

# iwconfig fallback
command -v iwconfig >/dev/null 2>&1 && iwconfig > "$ARTIFACTS/iwconfig.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true

# Keenetic-specific: ndmc for WiFi info
if command -v ndmc >/dev/null 2>&1; then
  ndmc -c "show interface WifiMaster0" > "$ARTIFACTS/wifi_master0.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  ndmc -c "show interface WifiMaster1" > "$ARTIFACTS/wifi_master1.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  ndmc -c "show interface WifiMaster0/AccessPoint0" > "$ARTIFACTS/wifi_ap0.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  ndmc -c "show interface WifiMaster1/AccessPoint0" > "$ARTIFACTS/wifi_ap1.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  ndmc -c "show associations" > "$ARTIFACTS/wifi_associations.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
fi

# Proc wireless
cat /proc/net/wireless > "$ARTIFACTS/proc_wireless.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true

# Wifi-related dmesg
dmesg 2>/dev/null | grep -iE 'wifi|wlan|80211|ath|mt76|rtw|brcm' > "$ARTIFACTS/dmesg_wifi.txt" 2>/dev/null || true

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"wifi.radio","status":"$status","metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
