# Collector Plugin Guide

## Structure

Each collector lives in `collectors/<id>/` with:
- `plugin.json` — metadata, dependencies, limits
- `run.sh` — executable collection script

## plugin.json Required Fields

| Field | Type | Description |
|---|---|---|
| `id` | string | Stable collector ID (e.g., `system.base`) |
| `name` | string | Human-readable name |
| `version` | string | SemVer version |
| `contract_version` | int | Framework contract version |
| `category` | string | Category for grouping |
| `requires_root` | bool | Needs root to run |
| `dangerous` | bool | Modifies system state |
| `dependencies.commands` | array | Required commands |
| `dependencies.files` | array | Required files |
| `estimated_cost` | object | CPU/RAM/IO/time estimates |
| `timeout_s` | int | Max execution time |
| `max_output_mb` | int | Max output size |
| `privacy_tags` | array | Sensitive data types in output |

## Environment Variables

| Variable | Description |
|---|---|
| `COLLECTOR_ID` | This collector's ID |
| `COLLECTOR_WORKDIR` | Write output here |
| `TOOL_BASE_DIR` | Installation prefix |
| `TOOL_REPORT_ID` | Current report ID |
| `RESEARCH_MODE` | light/medium/full/extreme |
| `PERF_MODE` | lite/middle/hard/auto |
| `TIMEOUT_S` | Allocated timeout |
| `TOOL_SANDBOX` | 1 if sandbox mode |

## Output Contract

1. Write artifacts to `$COLLECTOR_WORKDIR/artifacts/`
2. Create `$COLLECTOR_WORKDIR/result.json` (schema: result.schema.json)
3. Exit codes: 0=OK, 1=SOFT_FAIL, 2=HARD_FAIL

## Creating a New Collector

```shell
scripts/new_collector.sh wifi.scan wifi
```

## CI Checklist

- [ ] plugin.json valid against schema
- [ ] version is SemVer
- [ ] contract_version is numeric
- [ ] privacy_tags from allowed vocabulary
- [ ] dependencies declared
- [ ] estimated_cost populated
- [ ] timeout_s > 0, max_output_mb > 0
- [ ] run.sh exists and is executable
- [ ] Listed in registry.json
