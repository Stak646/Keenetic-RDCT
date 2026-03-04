# WebUI Guide

## Pages
- **Dashboard**: Status, quick actions
- **Preflight**: Environment check, warnings, cost estimates
- **Progress**: Current collector, queue, Governor metrics
- **Reports**: List, download, delete, view manifest/redaction
- **Inventory**: Port→Process→Package map with search/filters
- **Checks**: Anomalies/changes by category and severity
- **Chain**: Baseline/delta visualization, rebase/compact
- **Device Info**: Model, firmware, RAM, storage, temperature
- **App Manager**: Service status, start/stop (admin+dangerous_ops)
- **Settings**: Language, mode selection

## Access
- URL: http://127.0.0.1:<port> (shown after start)
- Auth: Bearer token from `var/.auth_token`
- Roles: admin (full), readonly (view only)

## Security
- Bind: localhost only by default
- Token required for all API calls
- CSRF: Origin header check
- Rate limiting: 60 req/min general, 5 req/min heavy ops
