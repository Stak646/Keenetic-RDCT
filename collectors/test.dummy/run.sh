#!/bin/sh
mkdir -p "$COLLECTOR_WORKDIR/artifacts"
echo "dummy output" > "$COLLECTOR_WORKDIR/artifacts/dummy.txt"
cat > "$COLLECTOR_WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"test.dummy","status":"OK","duration_ms":10,"metrics":{"output_size_bytes":12,"commands_run":1},"data":{"test":"ok"},"artifacts":["artifacts/dummy.txt"],"errors":[]}
REOF
exit 0
