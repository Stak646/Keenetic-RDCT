# Inventory & Correlation

## Reading inventory.json

Each entry maps: `port → PID → executable → opkg package → config paths → endpoints`

## Warnings
- `external_bind`: Port listening on 0.0.0.0 (accessible from WAN)
- `no_auth_detected`: Service without authentication

## Using for Troubleshooting
1. Find the problematic port in inventory
2. Trace to process and package
3. Check config files and endpoints
4. Compare with baseline using `inventory_delta.json`
