# Testing Matrix — Матрица режимов

## Smoke-тесты по осям

| | Lite | Middle | Hard | Auto |
|---|---|---|---|---|
| **Light** | ✅ CI | manual | manual | manual |
| **Medium** | manual | ✅ CI | manual | manual |
| **Full** | manual | manual | ✅ CI | manual |
| **Extreme** | manual | manual | manual | ✅ CI |

CI: минимум 2 комбинации (Light+Lite, Full+Auto).

## Тесты по категориям

| Тест | Тип | Описание |
|---|---|---|
| Schema validation | Unit | Примеры vs JSON Schema 2020-12 |
| L10n coverage | Unit | ru.json ↔ en.json ключи |
| Safe defaults | Unit | Нет 0.0.0.0, dangerous_ops=false |
| UTF-8 | Unit | Все JSON/MD/CSV |
| Sandbox Light+Lite | Integration | Полный прогон с фикстурами |
| Sandbox Full+Auto | Integration | Полный прогон с фикстурами |
| Self-mirror | Negative | output_dir в путях зеркала → CRITICAL |
| Timeout | Negative | Зависший collector → TIMEOUT |
| ENOSPC | Negative | Нет места → partial snapshot |
| OOM | Negative | Высокая нагрузка → Governor throttle |
| No Entware | Edge | Без /opt → graceful skip |
| Golden snapshot | Regression | Сравнение структуры + schemas |

## Sandbox стабильность (Step 638)
В sandbox_mode поддерживается подмена времени и идентификаторов для стабильных golden snapshots.

## Финальная матрица (Step 988)
| | Lite | Middle | Hard | Auto |
|---|---|---|---|---|
| Light | ✅ CI | ✅ Manual | ✅ Manual | ✅ Manual |
| Medium | ✅ Manual | ✅ CI | ✅ Manual | ✅ Manual |
| Full | ✅ Manual | ✅ Manual | ✅ CI | ✅ Manual |
| Extreme | ✅ Manual | ✅ Manual | ✅ Manual | ✅ CI |
