# Config Reference (MVP)

Config file: `config/rdct.json` under the base path on USB.

Important keys:

- `storage.base_path` – must be on external USB mount
- `modes.research_mode` – light|medium|full|extreme
- `modes.performance_mode` – lite|middle|hard|auto
- `modes.redaction.enabled` / `modes.redaction.level`
- `modes.mirror_policy.enabled` – enables Mirror collector
- `modes.network_policy.web_probe_allowed` – allow local HTTP probing (disabled in light by default)
- `modes.incremental_policy.enabled` + `baseline_frequency_runs`
- `modes.adaptive_policy.require_confirmation_for_risky` – Policy Engine will not auto-run medium+ risk actions
- `limits.max_concurrency` / `limits.collector_timeout_sec`
- `server.bind` / `server.port` / `server.token`
