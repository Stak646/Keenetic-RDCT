# API Reference (MVP)

All `/api/*` endpoints require token auth:

- Header: `X-RDCT-Token: <token>`
- or: `Authorization: Bearer <token>`

## Endpoints

- `GET /api/v1/status`
- `POST /api/v1/run/start` body: `{ "research_mode": "...", "performance_mode": "...", "baseline": false }`
- `POST /api/v1/run/stop`
- `GET /api/v1/reports`
- `GET /api/v1/reports/<run_id>/manifest`
- `GET /api/v1/reports/<run_id>/download`
- `GET /api/v1/reports/<run_id>/file/<relative_path...>`

Note: file access is restricted to the report snapshot directory.
