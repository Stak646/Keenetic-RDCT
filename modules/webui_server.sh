#!/bin/sh
# modules/webui_server.sh — Lightweight HTTP server for WebUI
# Steps 941-964

WEBUI_PID=""
WEBUI_PORT=""

# Step 941: Start WebUI server
webui_start() {
  local prefix="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
  local bind=$(config_get webui_bind 2>/dev/null || echo "127.0.0.1")
  local port_start=$(config_get webui_port_range_start 2>/dev/null || echo 5000)
  local port_end=$(config_get webui_port_range_end 2>/dev/null || echo 5099)
  local configured_port=$(config_get webui_port 2>/dev/null)
  local static_dir="$prefix/web/static"
  local token_file="$prefix/var/.auth_token"
  
  # Step 942: Port selection
  if [ -n "$configured_port" ] && [ "$configured_port" != "null" ]; then
    WEBUI_PORT="$configured_port"
  else
    WEBUI_PORT=$(webui_find_port "$bind" "$port_start" "$port_end")
  fi
  
  if [ -z "$WEBUI_PORT" ]; then
    log_event "ERROR" "webui" "webui.port_fail" "errors.E003" 2>/dev/null
    return 1
  fi
  
  # Step 942: Reject privileged ports
  if [ "$WEBUI_PORT" -lt 1024 ] 2>/dev/null; then
    log_event "ERROR" "webui" "webui.privileged_port" "errors.E003" \
      "\"port\":$WEBUI_PORT" 2>/dev/null
    return 1
  fi
  
  # Step 943: Save port
  echo "$WEBUI_PORT" > "$prefix/run/webui.port"
  
  log_event "INFO" "webui" "webui.start" "webui.started" \
    "\"bind\":\"$bind\",\"port\":$WEBUI_PORT" 2>/dev/null
  audit_log "webui_start" "system" "system" "ok" "\"bind\":\"$bind\",\"port\":$WEBUI_PORT" 2>/dev/null
  
  # Start Python HTTP server (if available)
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import http.server, socketserver, os, json, time, hashlib

PORT = $WEBUI_PORT
BIND = '$bind'
PREFIX = '$prefix'
TOKEN_FILE = '$token_file'
STATIC = '$static_dir'

def load_token():
    try:
        with open(TOKEN_FILE) as f:
            return f.read().strip()
    except:
        return ''

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=STATIC, **kwargs)
    
    # Step 944: Bearer token auth
    def check_auth(self):
        token = load_token()
        if not token:
            return True
        auth = self.headers.get('Authorization', '')
        if auth == f'Bearer {token}':
            return True
        # Check query param fallback
        if f'token={token}' in (self.path.split('?')[1] if '?' in self.path else ''):
            return True
        return False
    
    # Step 945: Role check
    def get_role(self):
        # Simplified: token = admin, no token = readonly (if allowed)
        if self.check_auth():
            return 'admin'
        return 'readonly'
    
    def do_GET(self):
        path = self.path.split('?')[0]
        
        # Step 947: /health — no auth required
        if path == '/health':
            self.send_json({'status': 'ok', 'version': open(f'{PREFIX}/VERSION').read().strip() if os.path.exists(f'{PREFIX}/VERSION') else 'unknown'})
            return
        
        # Auth for API endpoints
        if path.startswith('/api/') and not self.check_auth():
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b'{\"error\":\"unauthorized\"}')
            return
        
        # Step 949: Origin check (CSRF)
        origin = self.headers.get('Origin', '')
        if origin and not origin.startswith(f'http://{BIND}'):
            self.send_response(403)
            self.end_headers()
            return
        
        # API endpoints
        if path == '/api/progress':
            state_file = f'{PREFIX}/run/state.json'
            if os.path.exists(state_file):
                self.send_file_json(state_file)
            else:
                self.send_json({'state': 'idle'})
        elif path == '/api/reports':
            reports = []
            rdir = f'{PREFIX}/reports'
            if os.path.isdir(rdir):
                for d in sorted(os.listdir(rdir)):
                    if os.path.isdir(f'{rdir}/{d}'):
                        reports.append({'id': d})
            self.send_json({'reports': reports})
        elif path == '/api/preflight':
            self.send_json({'message': 'Use POST to run preflight'})
        elif path.startswith('/api/i18n/'):
            lang = path.split('/')[-1]
            i18n_file = f'{PREFIX}/i18n/{lang}.json'
            if os.path.exists(i18n_file):
                self.send_file_json(i18n_file)
            else:
                self.send_json({})
        elif path == '/api/metrics':
            # Step 948
            gov = f'{PREFIX}/run/governor.json'
            self.send_file_json(gov) if os.path.exists(gov) else self.send_json({})
        else:
            super().do_GET()
    
    def send_json(self, data):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    
    def send_file_json(self, path):
        try:
            with open(path) as f:
                self.send_json(json.load(f))
        except:
            self.send_json({})
    
    def log_message(self, format, *args):
        pass  # Suppress default logging

with socketserver.TCPServer((BIND, PORT), Handler) as httpd:
    httpd.serve_forever()
" &
    WEBUI_PID=$!
    echo "$WEBUI_PID" > "$prefix/run/webui.pid"
    
    echo "WebUI: http://$bind:$WEBUI_PORT"
  else
    log_event "WARN" "webui" "webui.no_python" "errors.E013" 2>/dev/null
    echo "WebUI requires python3. Use CLI instead."
    return 1
  fi
}

# Step 942: Find free port
webui_find_port() {
  local bind="$1" start="$2" end="$3"
  local port=$start
  while [ "$port" -le "$end" ]; do
    if ! command -v ss >/dev/null 2>&1 || ! ss -tln 2>/dev/null | grep -q ":$port "; then
      echo "$port"
      return 0
    fi
    port=$((port + 1))
  done
  return 1
}

webui_stop() {
  local prefix="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
  local pid_file="$prefix/run/webui.pid"
  if [ -f "$pid_file" ]; then
    kill "$(cat "$pid_file")" 2>/dev/null
    rm -f "$pid_file" "$prefix/run/webui.port"
    log_event "INFO" "webui" "webui.stop" "webui.started" 2>/dev/null
  fi
}
