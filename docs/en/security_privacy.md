# Security & Privacy

## Redaction Modes

| Mode | Behavior | Use Case |
|---|---|---|
| Light | Zeroize passwords/tokens/keys | Safe sharing |
| Medium | + Hash IPs/MACs, partial mask tokens | Support tickets |
| Full | Preserve all, flag findings | Deep investigation |
| Extreme | Preserve all, no masking | Forensic analysis |

## What Gets Redacted (Light/Medium)
- Passwords → `***REDACTED***`
- Bearer tokens → `Bearer ***REDACTED***`
- Private keys → `***PRIVATE KEY REDACTED***`
- IPs → hashed octets (Medium)
- MACs → hashed (Medium)

## Sanitize Export
```shell
keenetic-debug sanitize <report_id>
```
Creates a copy with forced Light-mode redaction and removes config files.

## Full/Extreme Warning
Full and Extreme modes preserve sensitive data. Use only when necessary.
CLI requires `--i-understand` flag for Full/Extreme modes.
