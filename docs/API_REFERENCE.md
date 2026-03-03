# API Reference

All `/api/*` endpoints require token auth:

- Header: `X-RDCT-Token: <token>`
- or: `Authorization: Bearer <token>`

## Endpoints

### Status / progress

- `GET /api/v1/status`
- `GET /api/v1/progress`
- `GET /api/v1/plan` (best-effort: most recent run)

### Run control

- `POST /api/v1/run/start` body: `{ "research_mode": "light|medium|full|extreme", "performance_mode": "balanced|fast|safe", "baseline": false }`
- `POST /api/v1/run/stop`
- `POST /api/v1/run/pause`
- `POST /api/v1/run/resume`

### Config

- `GET /api/v1/config`
- `POST /api/v1/config` body: JSON patch object merged into config

### Reports

- `GET /api/v1/reports` (list)
- `GET /api/v1/reports/<run_id>` (manifest)
- `GET /api/v1/reports/<run_id>/file?path=<relative_path>`
- `POST /api/v1/reports/<run_id>/export` body: `{ "level": "strict|normal|off" }`
- `POST /api/v1/reports/<run_id>/delete`

Legacy:

- `GET /download/<run_id>.tar.gz` (if a bundle exists at `<base>/reports/<run_id>/<run_id>.tar.gz`)

### Apps (Allowlist App Manager)

- `GET /api/v1/apps` (catalog + status)
- `GET /api/v1/apps/status`
- `POST /api/v1/apps/<app_id>/install`
- `POST /api/v1/apps/<app_id>/update`

Notes:

- File access is restricted to the report snapshot directory.
- App install/update requires Entware (`/opt`) on USB and network access.
