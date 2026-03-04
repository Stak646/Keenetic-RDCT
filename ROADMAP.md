# ROADMAP.md — Дорожная карта / Roadmap

## Alpha — Framework
- [ ] Структура репозитория, CI, схемы, контракты
- [ ] Core: оркестрация, plan, execute (1 worker)
- [ ] Preflight: capability detect, plan.json
- [ ] Governor: базовый мониторинг CPU/RAM/disk
- [ ] 3 reference collectors (system.base, network.base, storage.fs)
- [ ] Packager: tar.gz + manifest
- [ ] CLI: базовые команды, --lang
- [ ] install.sh: draft

## Beta — Основные collectors + WebUI/CLI
- [ ] 20 ключевых collectors по всем категориям ТЗ
- [ ] WebUI: HTTP API + SPA (Preflight, Progress, Reports)
- [ ] CLI: полный набор команд
- [ ] Redaction engine: Light/Medium masking
- [ ] InventoryBuilder: корреляции
- [ ] StateDB: baseline/delta
- [ ] ChecksEngine: базовые проверки
- [ ] i18n: RU/EN для CLI и WebUI

## RC — Документация + CI + Стабилизация
- [ ] Документация RU/EN: все обязательные разделы
- [ ] CI: schema validation, l10n coverage, golden snapshots
- [ ] Тестирование: матрица режимов, negative tests
- [ ] install.sh: pinned sha256, offline bundle
- [ ] Security: аудит WebUI, rate limiting, CSRF

## Release — DoD
- [ ] Все пункты DOD.md выполнены
- [ ] GitHub Release: артефакты по архитектурам
- [ ] Release notes RU/EN
- [ ] Support playbook
