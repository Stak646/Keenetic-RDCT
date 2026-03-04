# Release Checklist

## Перед релизом

- [ ] Обновить `version.json` (version, date)
- [ ] Обновить `CHANGELOG.md` (новая секция)
- [ ] Прогнать полную матрицу режимов (Light/Medium/Full/Extreme × Lite/Middle/Hard/Auto)
- [ ] Убедиться что CI зелёный (lint + schemas + l10n + docs + safe-defaults + utf8)
- [ ] Обновить golden snapshots если схемы менялись
- [ ] Проверить install.sh на целевом устройстве (хотя бы mipsel)
- [ ] Проверить WebUI стартует, порт автоматически выбирается
- [ ] Проверить CLI `--help` на RU и EN
- [ ] Обновить docs/ru и docs/en (все изменения)
- [ ] Проверить docs/compatibility.md (новые collectors/команды)
- [ ] Проверить config.example.json и config.minimal.json (новые поля)

## Сборка релиза

- [ ] `git tag v<X.Y.Z>`
- [ ] CI: release.yml собирает артефакты (online + offline × 3 arch)
- [ ] CI: release_manifest_gen.sh → release-manifest.json с sha256
- [ ] GitHub Release: заметки из CHANGELOG, артефакты, manifest

## После релиза

- [ ] Убедиться install.sh скачивает новую версию
- [ ] Проверить sha256 совпадают
- [ ] Обновить ROADMAP.md
- [ ] Создать milestone для следующего релиза
