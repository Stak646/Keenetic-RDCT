# API Reference

## Аутентификация

Все `/api/*` требуют токен.

- Заголовок: `X-RDCT-Token: <token>`
- или: `Authorization: Bearer <token>`

Токен хранится в:

- `<base>/config/rdct.json` → `server.token`

## Endpoints

### Статус / прогресс

- `GET /api/v1/status`
- `GET /api/v1/progress`
- `GET /api/v1/plan` (best-effort: план последнего запуска)

### Управление запуском

- `POST /api/v1/run/start` body: `{ "research_mode": "light|medium|full|extreme", "performance_mode": "balanced|fast|safe", "baseline": false }`
- `POST /api/v1/run/stop`
- `POST /api/v1/run/pause`
- `POST /api/v1/run/resume`

### Конфиг

- `GET /api/v1/config`
- `POST /api/v1/config` body: JSON patch (мерджится в конфиг)

### Отчёты

- `GET /api/v1/reports` (список)
- `GET /api/v1/reports/<run_id>` (manifest)
- `GET /api/v1/reports/<run_id>/file?path=<relative_path>`
- `POST /api/v1/reports/<run_id>/export` body: `{ "level": "strict|normal|off" }`
- `POST /api/v1/reports/<run_id>/delete`

Legacy:

- `GET /download/<run_id>.tar.gz` (если bundle существует в `<base>/reports/<run_id>/<run_id>.tar.gz`)

### Apps (Allowlist App Manager)

- `GET /api/v1/apps` (catalog + status)
- `GET /api/v1/apps/status`
- `POST /api/v1/apps/<app_id>/install`
- `POST /api/v1/apps/<app_id>/update`

## Примечания

- Доступ к файлам ограничен директорией snapshot.
- Установка/обновление apps требует Entware (`/opt`) на USB и интернет.
