#!/usr/bin/env python3
"""Keenetic-RDCT WebUI Server — full-featured API"""
import http.server, socketserver, os, json, sys, time, subprocess, platform, re, signal

# Config from env or defaults
PORT = int(os.environ.get("RDCT_PORT", 5000))
BIND = os.environ.get("RDCT_BIND", "0.0.0.0")
PREFIX = os.environ.get("RDCT_PREFIX", "/opt/keenetic-debug")
STATIC = os.path.join(PREFIX, "web", "static")
TOKEN_FILE = os.path.join(PREFIX, "var", ".auth_token")
CONFIG_FILE = os.path.join(PREFIX, "config.json")

# Known packages for app manager
KNOWN_APPS = {
    "nfqws-keenetic": {
        "name": "NFQWS Keenetic",
        "repo": "https://anonym-tsk.github.io/nfqws-keenetic/all",
        "opkg_conf": "/opt/etc/opkg/nfqws-keenetic.conf",
        "package": "nfqws-keenetic",
        "icon": "🛡️",
        "description_ru": "Обход блокировок через NFQUEUE (оригинал)",
        "description_en": "DPI bypass via NFQUEUE (original)",
        "conflicts": [],
        "service": "S51nfqws-keenetic"
    },
    "nfqws2-keenetic": {
        "name": "NFQWS2 Keenetic",
        "repo": "https://nfqws.github.io/nfqws2-keenetic/all",
        "opkg_conf": "/opt/etc/opkg/nfqws2-keenetic.conf",
        "package": "nfqws2-keenetic",
        "icon": "🛡️",
        "description_ru": "Обход блокировок через NFQUEUE v2 (улучшенная)",
        "description_en": "DPI bypass via NFQUEUE v2 (improved)",
        "conflicts": ["nfqws-keenetic"],
        "service": "S51nfqws2-keenetic"
    },
    "nfqws-keenetic-web": {
        "name": "NFQWS Keenetic Web",
        "repo": "https://nfqws.github.io/nfqws-keenetic-web/all",
        "opkg_conf": "/opt/etc/opkg/nfqws-keenetic-web.conf",
        "package": "nfqws-keenetic-web",
        "icon": "🌐",
        "description_ru": "Веб-интерфейс для NFQWS",
        "description_en": "Web interface for NFQWS",
        "conflicts": [],
        "service": None
    },
    "hydraroute": {
        "name": "HydraRoute Neo",
        "repo": "https://raw.githubusercontent.com/Ground-Zerro/HydraRoute/main/install.sh",
        "opkg_conf": None,
        "package": None,
        "icon": "🐉",
        "install_cmd": "curl -fsSL https://raw.githubusercontent.com/Ground-Zerro/HydraRoute/main/install.sh | sh",
        "description_ru": "Маршрутизация доменов через VPN для Keenetic",
        "description_en": "Domain-based VPN routing for Keenetic",
        "conflicts": ["magitrickle"],
        "service": None,
        "check_installed": "/opt/etc/init.d/S52hydra*",
        "legacy": ["HydraRoute-Classic", "HydraRoute-Relic"]
    },
    "magitrickle": {
        "name": "MagiTrickle",
        "repo": "https://gitlab.com/magitrickle/magitrickle",
        "opkg_conf": None,
        "package": None,
        "icon": "🎩",
        "install_cmd": "curl -fsSL https://magitrickle.github.io/install.sh | sh",
        "description_ru": "Точечная маршрутизация по доменам",
        "description_en": "Domain-based traffic routing",
        "conflicts": ["hydraroute"],
        "service": None,
        "check_installed": "/opt/etc/init.d/*magitrickle*"
    },
    "awg-manager": {
        "name": "AWG Manager",
        "repo": "https://github.com/hoaxisr/awg-manager",
        "opkg_conf": None,
        "package": None,
        "icon": "🔐",
        "install_cmd": "curl -fsSL https://raw.githubusercontent.com/hoaxisr/awg-manager/main/install.sh | sh",
        "description_ru": "Менеджер туннелей AmneziaWG с веб-интерфейсом",
        "description_en": "AmneziaWG tunnel manager with web UI",
        "conflicts": [],
        "service": None,
        "check_installed": "/opt/etc/init.d/*awg*"
    }
}


def load_token():
    try: return open(TOKEN_FILE).read().strip()
    except: return ""

def run_cmd(cmd, timeout=30):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return {"exit_code": r.returncode, "stdout": r.stdout.strip(), "stderr": r.stderr.strip()}
    except subprocess.TimeoutExpired:
        return {"exit_code": 124, "stdout": "", "stderr": "timeout"}
    except Exception as e:
        return {"exit_code": 1, "stdout": "", "stderr": str(e)}

def detect_device():
    """Full device detection including model"""
    info = {
        "arch": platform.machine(),
        "kernel": platform.release(),
        "hostname": platform.node(),
    }
    # Model from /proc/cpuinfo
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if "system type" in line.lower() or "machine" in line.lower() or "hardware" in line.lower():
                    info["cpu_model"] = line.split(":")[-1].strip()
                    break
    except: pass

    # Try ndmc for Keenetic model
    r = run_cmd("ndmc -c 'show version' 2>/dev/null | head -20", timeout=5)
    if r["exit_code"] == 0 and r["stdout"]:
        for line in r["stdout"].split("\n"):
            if "device:" in line.lower() or "model:" in line.lower() or "description:" in line.lower():
                info["model"] = line.split(":")[-1].strip()
            if "title:" in line.lower():
                info["model_title"] = line.split(":")[-1].strip()
            if "release:" in line.lower() or "version:" in line.lower():
                info["firmware"] = line.split(":")[-1].strip()
            if "sandbox:" in line.lower() or "region:" in line.lower():
                info["region"] = line.split(":")[-1].strip()

    # RCI JSON for model
    r = run_cmd("ndmc -c 'show version' 2>/dev/null", timeout=5)
    if r["exit_code"] == 0:
        try:
            # Try parse as JSON (some versions output JSON)
            d = json.loads(r["stdout"])
            info["model"] = d.get("device", info.get("model", ""))
            info["firmware"] = d.get("release", info.get("firmware", ""))
            info["model_title"] = d.get("title", info.get("model_title", ""))
        except: pass

    # Fallback model detection from /tmp or hostname
    if "model" not in info or not info["model"]:
        r2 = run_cmd("cat /tmp/sysinfo/model 2>/dev/null || cat /proc/device-tree/model 2>/dev/null || echo ''", timeout=3)
        info["model"] = r2["stdout"] or info.get("hostname", "Unknown")

    # System metrics
    try:
        with open("/proc/uptime") as f: info["uptime_s"] = float(f.read().split()[0])
        info["uptime_human"] = f"{int(info['uptime_s']//86400)}d {int((info['uptime_s']%86400)//3600)}h {int((info['uptime_s']%3600)//60)}m"
    except: pass
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if "MemTotal" in line: info["ram_total_kb"] = int(line.split()[1])
                if "MemAvailable" in line: info["ram_free_kb"] = int(line.split()[1])
                if "MemFree" in line and "ram_free_kb" not in info: info["ram_free_kb"] = int(line.split()[1])
        if "ram_total_kb" in info:
            info["ram_total_mb"] = info["ram_total_kb"] // 1024
            info["ram_used_pct"] = round(100 * (1 - info.get("ram_free_kb",0) / info["ram_total_kb"]), 1)
    except: pass
    try:
        with open("/proc/loadavg") as f:
            parts = f.read().split()
            info["load_1m"] = parts[0]; info["load_5m"] = parts[1]; info["load_15m"] = parts[2]
    except: pass
    # Disk
    r = run_cmd("df -m /opt 2>/dev/null | tail -1", timeout=5)
    if r["stdout"]:
        parts = r["stdout"].split()
        if len(parts) >= 4:
            info["disk_total_mb"] = parts[1]
            info["disk_used_mb"] = parts[2]
            info["disk_free_mb"] = parts[3]

    # CPU count
    try:
        with open("/proc/cpuinfo") as f:
            info["cpu_count"] = sum(1 for l in f if l.startswith("processor"))
    except: pass

    # Temperature
    r = run_cmd("cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1", timeout=3)
    if r["stdout"]:
        try: info["temp_c"] = round(int(r["stdout"]) / 1000, 1)
        except: pass

    info["entware"] = os.path.exists("/opt/bin/opkg")
    return info

def get_app_status():
    """Check installed status and running state of known apps"""
    apps = []
    for aid, app in KNOWN_APPS.items():
        status = {"id": aid, **app, "installed": False, "running": False, "version": ""}

        # Check via opkg
        if app.get("package"):
            r = run_cmd(f"opkg status {app['package']} 2>/dev/null | head -5", timeout=5)
            if "Status: install" in r["stdout"]:
                status["installed"] = True
                for line in r["stdout"].split("\n"):
                    if line.startswith("Version:"):
                        status["version"] = line.split(":")[1].strip()

        # Check via glob pattern
        if app.get("check_installed"):
            import glob
            if glob.glob(app["check_installed"]):
                status["installed"] = True

        # Check running
        if app.get("service"):
            r = run_cmd(f"ls /opt/etc/init.d/{app['service']}* 2>/dev/null && /opt/etc/init.d/{app['service']}* status 2>/dev/null", timeout=5)
            if "running" in r["stdout"].lower() or "alive" in r["stdout"].lower():
                status["running"] = True
        else:
            # Generic check by name
            r = run_cmd(f"ps w 2>/dev/null | grep -i '{aid}' | grep -v grep", timeout=3)
            if r["stdout"]:
                status["running"] = True

        # Check conflicts
        status["conflict_warning"] = ""
        for cid in app.get("conflicts", []):
            if cid in KNOWN_APPS:
                capp = KNOWN_APPS[cid]
                # Check if conflict is installed
                if capp.get("package"):
                    r = run_cmd(f"opkg status {capp['package']} 2>/dev/null | grep 'Status: install'", timeout=3)
                    if r["stdout"]:
                        status["conflict_warning"] = f"Конфликт с {capp['name']}! / Conflicts with {capp['name']}!"
                if capp.get("check_installed"):
                    import glob
                    if glob.glob(capp["check_installed"]):
                        status["conflict_warning"] = f"Конфликт с {capp['name']}! / Conflicts with {capp['name']}!"

        # Check legacy versions (HydraRoute)
        if app.get("legacy"):
            for leg in app["legacy"]:
                r = run_cmd(f"ls /opt/etc/init.d/*{leg.lower().replace('-','')}* 2>/dev/null || opkg status {leg.lower()} 2>/dev/null | grep Status", timeout=3)
                if r["stdout"]:
                    status["legacy_detected"] = leg
                    status["upgrade_hint"] = f"Обнаружена старая версия ({leg}). Рекомендуется обновить на Neo."

        apps.append(status)
    return apps


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=STATIC, **kw)

    def check_auth(self):
        token = load_token()
        if not token: return True
        auth = self.headers.get("Authorization", "")
        if auth == f"Bearer {token}": return True
        if "?" in self.path:
            qs = self.path.split("?", 1)[1]
            if f"token={token}" in qs: return True
        return False

    def send_json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def send_file_json(self, path):
        try:
            with open(path) as f: self.send_json(json.load(f))
        except: self.send_json({"error": f"file not found: {os.path.basename(path)}"}, 404)

    def read_body(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            if length > 0: return json.loads(self.rfile.read(length))
        except: pass
        return {}

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?")[0]

        if path == "/health":
            ver = "unknown"
            try: ver = open(os.path.join(PREFIX, "VERSION")).read().strip()
            except: pass
            self.send_json({"status": "ok", "version": ver, "port": PORT})
            return

        if path.startswith("/api/"):
            if not self.check_auth():
                self.send_json({"error": "unauthorized"}, 401)
                return
            self._handle_api_get(path)
            return

        super().do_GET()

    def _handle_api_get(self, path):
        if path == "/api/progress":
            sf = os.path.join(PREFIX, "run", "state.json")
            if os.path.exists(sf): self.send_file_json(sf)
            else: self.send_json({"state": "idle"})

        elif path == "/api/device":
            self.send_json(detect_device())

        elif path == "/api/config":
            if os.path.exists(CONFIG_FILE): self.send_file_json(CONFIG_FILE)
            else: self.send_json({})

        elif path == "/api/reports":
            rdir = os.path.join(PREFIX, "reports")
            reports = []
            if os.path.isdir(rdir):
                for d in sorted(os.listdir(rdir), reverse=True):
                    dp = os.path.join(rdir, d)
                    if os.path.isdir(dp):
                        sz = sum(os.path.getsize(os.path.join(dp,f)) for f in os.listdir(dp) if os.path.isfile(os.path.join(dp,f)))
                        reports.append({"id": d, "size_bytes": sz})
            self.send_json({"reports": reports})

        elif path == "/api/apps":
            self.send_json({"apps": get_app_status()})

        elif re.match(r"/api/report/[^/]+/(manifest|checks|inventory|redaction|summary|preflight|plan)", path):
            parts = path.split("/")
            rid, sub = parts[3], parts[4]
            fmap = {"manifest":"manifest.json","checks":"checks.json","inventory":"inventory.json",
                    "redaction":"redaction_report.json","summary":"summary.json","preflight":"preflight.json","plan":"plan.json"}
            self.send_file_json(os.path.join(PREFIX, "reports", rid, fmap.get(sub, sub+".json")))

        elif path.startswith("/api/i18n/"):
            lang = path.split("/")[-1]
            lf = os.path.join(PREFIX, "i18n", f"{lang}.json")
            if os.path.exists(lf): self.send_file_json(lf)
            else: self.send_json({})

        elif path == "/api/preflight":
            # Run actual preflight
            r = run_cmd(f"sh {PREFIX}/collectors/system.base/run.sh 2>&1; echo '---'; cat /proc/cpuinfo 2>/dev/null | head -5; echo '---'; df -h 2>/dev/null; echo '---'; ip addr show 2>/dev/null | head -30", timeout=15)
            caps = {}
            for cmd in ["ip","ss","iptables","opkg","tar","python3","curl","wget","jq","dmesg","wg","ndmc"]:
                caps[cmd] = run_cmd(f"command -v {cmd}", timeout=2)["exit_code"] == 0
            self.send_json({"capabilities": caps, "output": r["stdout"][:5000], "arch": platform.machine()})

        else:
            self.send_json({"error": "not found"}, 404)

    def do_POST(self):
        path = self.path.split("?")[0]
        if not self.check_auth():
            self.send_json({"error": "unauthorized"}, 401)
            return

        body = self.read_body()

        if path == "/api/start":
            mode = body.get("mode", "light")
            perf = body.get("perf", "lite")
            # Create a simple collection run
            report_id = f"report-{int(time.time())}"
            report_dir = os.path.join(PREFIX, "reports", report_id)
            os.makedirs(report_dir, exist_ok=True)
            os.makedirs(os.path.join(report_dir, "collectors"), exist_ok=True)

            # Write state
            state = {"state": "RUNNING", "report_id": report_id, "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
            with open(os.path.join(PREFIX, "run", "state.json"), "w") as f: json.dump(state, f)

            # Run collection in background
            cmd = f"cd {PREFIX} && sh -c '"
            cmd += f"export TOOL_BASE_DIR={PREFIX} COLLECTOR_WORKDIR={report_dir} TOOL_REPORT_ID={report_id} RESEARCH_MODE={mode} PERF_MODE={perf}; "
            # Run each collector
            cmd += f"for c in {PREFIX}/collectors/*/run.sh; do "
            cmd += f'  cid=$(basename $(dirname "$c")); '
            cmd += f'  [ "$cid" = "_template" ] && continue; '
            cmd += f'  echo "$cid" | grep -q "^test\\." && continue; '
            cmd += f'  mkdir -p {report_dir}/collectors/$cid/artifacts; '
            cmd += f'  export COLLECTOR_ID=$cid COLLECTOR_WORKDIR={report_dir}/collectors/$cid; '
            cmd += f'  timeout 30 sh "$c" >{report_dir}/collectors/$cid/stdout.log 2>&1 || true; '
            cmd += f"done; "
            # Write device info
            cmd += f"echo \'{json.dumps(detect_device())}\' > {report_dir}/device.json; "
            # Manifest
            cmd += f'echo \'{{"schema_id":"manifest","schema_version":"1","report_id":"{report_id}","created_at":"\'$(date -u +%Y-%m-%dT%H:%M:%SZ)\'"}}\' > {report_dir}/manifest.json; '
            # Done state
            cmd += f'echo \'{{"state":"DONE","report_id":"{report_id}"}}\' > {PREFIX}/run/state.json'
            cmd += "'"

            subprocess.Popen(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.send_json({"status": "started", "report_id": report_id})

        elif path == "/api/stop":
            with open(os.path.join(PREFIX, "run", "state.json"), "w") as f:
                json.dump({"state": "CANCELLED"}, f)
            self.send_json({"status": "cancelled"})

        elif path == "/api/config":
            # Save config
            try:
                with open(CONFIG_FILE, "w") as f:
                    json.dump(body, f, indent=2, ensure_ascii=False)
                self.send_json({"status": "saved"})
            except Exception as e:
                self.send_json({"error": str(e)}, 500)

        elif path == "/api/app/install":
            aid = body.get("app_id", "")
            app = KNOWN_APPS.get(aid)
            if not app:
                self.send_json({"error": f"Unknown app: {aid}"}, 400)
                return
            # opkg-based install
            if app.get("package") and app.get("repo"):
                cmds = [
                    f"mkdir -p /opt/etc/opkg",
                    f'echo "src/gz {aid} {app["repo"]}" > {app["opkg_conf"]}',
                    f"opkg update 2>&1",
                    f"opkg install {app['package']} 2>&1"
                ]
                output = ""
                for c in cmds:
                    r = run_cmd(c, timeout=60)
                    output += r["stdout"] + "\n" + r["stderr"] + "\n"
                self.send_json({"status": "done", "output": output.strip()})
            elif app.get("install_cmd"):
                r = run_cmd(app["install_cmd"], timeout=120)
                self.send_json({"status": "done", "output": r["stdout"] + "\n" + r["stderr"]})
            else:
                self.send_json({"error": "No install method"}, 400)

        elif path == "/api/app/remove":
            aid = body.get("app_id", "")
            app = KNOWN_APPS.get(aid)
            if not app:
                self.send_json({"error": f"Unknown app: {aid}"}, 400)
                return
            if app.get("package"):
                r = run_cmd(f"opkg remove {app['package']} 2>&1", timeout=30)
                if app.get("opkg_conf"):
                    run_cmd(f"rm -f {app['opkg_conf']}", timeout=5)
                self.send_json({"status": "done", "output": r["stdout"] + "\n" + r["stderr"]})
            else:
                self.send_json({"error": "Manual removal required"}, 400)

        elif path == "/api/app/control":
            aid = body.get("app_id", "")
            action = body.get("action", "status")  # start/stop/restart/status
            app = KNOWN_APPS.get(aid)
            if not app:
                self.send_json({"error": f"Unknown app: {aid}"}, 400)
                return
            import glob
            svc = None
            if app.get("service"):
                matches = glob.glob(f"/opt/etc/init.d/{app['service']}*")
                if matches: svc = matches[0]
            if not svc:
                # Try finding by app id
                matches = glob.glob(f"/opt/etc/init.d/*{aid.replace('-','')}*") + glob.glob(f"/opt/etc/init.d/*{aid}*")
                if matches: svc = matches[0]
            if svc:
                r = run_cmd(f"{svc} {action} 2>&1", timeout=15)
                self.send_json({"status": "done", "action": action, "output": r["stdout"] + "\n" + r["stderr"]})
            else:
                self.send_json({"error": "Service script not found"}, 404)

        elif path == "/api/preflight/run":
            # Run real preflight
            caps = {}
            for cmd in ["ip","ss","iptables","opkg","tar","python3","curl","wget","jq","dmesg","wg","ndmc","iw"]:
                caps[cmd] = run_cmd(f"command -v {cmd}", timeout=2)["exit_code"] == 0

            warnings = []
            # Check disk
            r = run_cmd("df -m /opt 2>/dev/null | tail -1 | awk '{print $4}'", timeout=5)
            free = int(r["stdout"]) if r["stdout"].isdigit() else 0
            if free < 50: warnings.append({"severity":"CRIT","msg":f"Low disk: {free}MB free"})
            elif free < 200: warnings.append({"severity":"WARN","msg":f"Disk space: {free}MB free"})

            # Check RAM
            r = run_cmd("awk '/MemAvailable/{print $2}' /proc/meminfo", timeout=3)
            ram_free = int(r["stdout"]) if r["stdout"].isdigit() else 0
            if ram_free < 32768: warnings.append({"severity":"WARN","msg":f"Low RAM: {ram_free//1024}MB available"})

            # List collectors
            collectors = []
            cdir = os.path.join(PREFIX, "collectors")
            if os.path.isdir(cdir):
                for d in sorted(os.listdir(cdir)):
                    if d.startswith("_") or d.startswith("test."): continue
                    pj = os.path.join(cdir, d, "plugin.json")
                    if os.path.exists(pj):
                        try:
                            with open(pj) as f: meta = json.load(f)
                            collectors.append({"id": d, "name": meta.get("name",d), "status": "INCLUDE",
                                "reason": "available", "timeout_s": meta.get("timeout_s",60)})
                        except:
                            collectors.append({"id": d, "name": d, "status": "SKIP", "reason": "invalid plugin.json"})

            self.send_json({"capabilities": caps, "warnings": warnings, "collectors": collectors,
                           "disk_free_mb": free, "ram_free_kb": ram_free})

        else:
            self.send_json({"error": "not found"}, 404)

    def log_message(self, fmt, *args): pass

print(f"Keenetic-RDCT WebUI: http://0.0.0.0:{PORT}", flush=True)
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer((BIND, PORT), Handler) as httpd:
    httpd.serve_forever()
