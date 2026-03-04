# Quick Start

## Install
```shell
curl -fsSL https://github.com/keenetic-debug/install.sh | sh
```

## Baseline Snapshot
```shell
keenetic-debug start --mode light --perf lite
```

## Incremental Snapshot
```shell
keenetic-debug start --mode medium --perf auto --snapshot-mode delta
```

## Download Report
```shell
keenetic-debug report list
keenetic-debug report download <report_id>
```

## Sanitize for Sharing
```shell
keenetic-debug sanitize <report_id>
```
