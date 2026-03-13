#!/usr/bin/env python3
"""Keenetic-RDCT WebUI Server v2 — fixed detection, working start, config UI"""
import http.server, socketserver, os, json, sys, time, subprocess, platform, re, glob, threading

PORT = int(os.environ.get("RDCT_PORT", 5000))
BIND = os.environ.get("RDCT_BIND", "0.0.0.0")
PREFIX = os.environ.get("RDCT_PREFIX", "/opt/keenetic-debug")
STATIC = os.path.join(PREFIX, "web", "static")
TOKEN_FILE = os.path.join(PREFIX, "var", ".auth_token")
CONFIG_FILE = os.path.join(PREFIX, "config.json")

# ─── Helpers ──────────────────────────────────────────────────────────────
def run(cmd, timeout=30):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip(), r.returncode
    except: return "", 1

def load_token():
    try: return open(TOKEN_FILE).read().strip()
    except: return ""

def load_config():
    try:
        with open(CONFIG_FILE) as f: return json.load(f)
    except: return {}

# ─── Known apps ───────────────────────────────────────────────────────────
APPS = [
  {"id":"nfqws-keenetic", "name":"NFQWS Keenetic","icon":"🛡️",
   "desc_ru":"Обход блокировок (оригинал Anonym-tsk)","desc_en":"DPI bypass (original)",
   "opkg":"nfqws-keenetic","repo_line":"src/gz nfqws-keenetic https://anonym-tsk.github.io/nfqws-keenetic/all",
   "svc_glob":["S51nfqws*","*nfqws-keenetic*"],"proc_grep":["nfqws"],
   "conflicts":[]},

  {"id":"nfqws2-keenetic","name":"NFQWS2 Keenetic","icon":"🛡️",
   "desc_ru":"Обход блокировок v2 (улучшенная)","desc_en":"DPI bypass v2 (improved)",
   "opkg":"nfqws2-keenetic","repo_line":"src/gz nfqws2-keenetic https://nfqws.github.io/nfqws2-keenetic/all",
   "svc_glob":["S51nfqws2*","*nfqws2*"],"proc_grep":["nfqws"],
   "conflicts":["nfqws-keenetic"]},

  {"id":"nfqws-keenetic-web","name":"NFQWS Keenetic Web","icon":"🌐",
   "desc_ru":"Веб-интерфейс для NFQWS","desc_en":"Web UI for NFQWS",
   "opkg":"nfqws-keenetic-web","repo_line":"src/gz nfqws-keenetic-web https://nfqws.github.io/nfqws-keenetic-web/all",
   "svc_glob":["*nfqws*web*"],"proc_grep":["php-fpm","php","nfqws.*web"],
   "conflicts":[]},

  {"id":"hydraroute","name":"HydraRoute Neo","icon":"🐉",
   "desc_ru":"Маршрутизация доменов через VPN","desc_en":"Domain-based VPN routing",
   "opkg":None,
   "install_cmd":"curl -fsSL https://raw.githubusercontent.com/Ground-Zerro/HydraRoute/main/install.sh | sh",
   "svc_glob":["*[Hh]ydra*","*hydraroute*","S52hydra*","S99hydra*"],
   "file_check":["/opt/etc/hydra","/opt/etc/HydraRoute","/opt/sbin/hydra","/opt/bin/hydra"],
   "proc_grep":["hydra","HydraRoute"],
   "conflicts":["magitrickle"],
   "legacy_glob":["*[Hh]ydra*[Cc]lassic*","*[Hh]ydra*[Rr]elic*"]},

  {"id":"magitrickle","name":"MagiTrickle","icon":"🎩",
   "desc_ru":"Точечная маршрутизация по доменам","desc_en":"Domain-based traffic routing",
   "opkg":None,
   "install_cmd":"curl -fsSL https://raw.githubusercontent.com/MagiTrickle/MagiTrickle/main/install.sh | sh",
   "svc_glob":["*[Mm]agi[Tt]rickle*","*magitrickle*"],
   "file_check":["/opt/etc/magitrickle","/opt/bin/magitrickle","/opt/sbin/magitrickle"],
   "proc_grep":["magitrickle","MagiTrickle"],
   "conflicts":["hydraroute"]},

  {"id":"awg-manager","name":"AWG Manager","icon":"🔐",
   "desc_ru":"Менеджер туннелей AmneziaWG","desc_en":"AmneziaWG tunnel manager",
   "opkg":None,
   "install_cmd":"curl -fsSL https://raw.githubusercontent.com/hoaxisr/awg-manager/main/install.sh | sh",
   "svc_glob":["*awg*","*amnezia*"],
   "file_check":["/opt/etc/awg","/opt/etc/awg-manager"],
   "proc_grep":["awg","amnezia"],
   "conflicts":[]},
]

def detect_app_status():
    """Detect installed/running for all known apps"""
    # Pre-fetch: list of init.d files and running processes
    initd_files = glob.glob("/opt/etc/init.d/*") if os.path.isdir("/opt/etc/init.d") else []
    ps_out, _ = run("ps w 2>/dev/null || ps aux 2>/dev/null")

    results = []
    for app in APPS:
        a = {**app, "installed": False, "running": False, "version": "",
             "conflict_warning": "", "upgrade_hint": "", "svc_path": ""}

        # ── Check installed ──
        # 1) opkg
        if app.get("opkg"):
            out, rc = run(f"opkg status {app['opkg']} 2>/dev/null")
            if "install ok installed" in out or "Status: install" in out:
                a["installed"] = True
                for line in out.split("\n"):
                    if line.startswith("Version:"): a["version"] = line.split(":",1)[1].strip()

        # 2) init.d service files
        if not a["installed"]:
            for pat in app.get("svc_glob", []):
                for f in initd_files:
                    bn = os.path.basename(f)
                    try:
                        if glob.fnmatch.fnmatch(bn, pat):
                            a["installed"] = True; a["svc_path"] = f; break
                    except: pass
                if a["installed"]: break

        # 3) file_check paths
        if not a["installed"]:
            for fp in app.get("file_check", []):
                if os.path.exists(fp):
                    a["installed"] = True; break

        # ── Find service path if not yet ──
        if not a["svc_path"]:
            for pat in app.get("svc_glob", []):
                for f in initd_files:
                    bn = os.path.basename(f)
                    try:
                        if glob.fnmatch.fnmatch(bn, pat):
                            a["svc_path"] = f; break
                    except: pass
                if a["svc_path"]: break

        # ── Check running ──
        # 1) Via service script status
        if a["svc_path"]:
            out, _ = run(f'"{a["svc_path"]}" status 2>/dev/null')
            low = out.lower()
            if "running" in low or "alive" in low or "started" in low or "active" in low:
                a["running"] = True

        # 2) Via ps grep (catch actual daemon processes)
        if not a["running"]:
            for pat in app.get("proc_grep", []):
                for line in ps_out.split("\n"):
                    if re.search(pat, line, re.IGNORECASE) and "grep" not in line:
                        a["running"] = True; break
                if a["running"]: break

        # ── Conflicts ──
        for cid in app.get("conflicts", []):
            for other in APPS:
                if other["id"] != cid: continue
                # Quick check if conflict is installed
                c_installed = False
                if other.get("opkg"):
                    out2, _ = run(f"opkg status {other['opkg']} 2>/dev/null | head -3")
                    if "install" in out2: c_installed = True
                if not c_installed:
                    for fp in other.get("file_check", []):
                        if os.path.exists(fp): c_installed = True; break
                if not c_installed:
                    for pat in other.get("svc_glob", []):
                        for f in initd_files:
                            try:
                                if glob.fnmatch.fnmatch(os.path.basename(f), pat): c_installed = True; break
                            except: pass
                        if c_installed: break
                if c_installed:
                    a["conflict_warning"] = f"⚠️ Может конфликтовать с {other['name']}! / May conflict with {other['name']}!"

        # ── Legacy (HydraRoute) ──
        for pat in app.get("legacy_glob", []):
            for f in initd_files:
                try:
                    if glob.fnmatch.fnmatch(os.path.basename(f), pat):
                        a["upgrade_hint"] = "Обнаружена старая версия! Рекомендуется обновить на Neo / Old version detected — upgrade to Neo recommended"
                except: pass

        # Clean up internal fields
        for k in ["svc_glob","proc_grep","file_check","opkg","repo_line","install_cmd","legacy_glob","conflicts"]:
            a.pop(k, None)

        results.append(a)
    return results

# ─── Device detection ─────────────────────────────────────────────────────
def detect_device():
    info = {"arch": platform.machine(), "kernel": platform.release(), "hostname": platform.node()}

    # Keenetic model via ndmc
    out, rc = run("ndmc -c 'show version' 2>/dev/null", 5)
    if rc == 0 and out:
        for line in out.split("\n"):
            ll = line.strip().lower()
            kv = line.split(":",1)
            if len(kv) == 2:
                k, v = kv[0].strip().lower(), kv[1].strip()
                if k in ("device","model"): info["model"] = v
                elif k == "title": info["model_title"] = v
                elif k in ("release","version","sw_version"): info["firmware"] = v
                elif k == "region": info["region"] = v
                elif k == "hw_id": info["hw_id"] = v
        # Try JSON parse
        try:
            d = json.loads(out)
            for k in ("device","model","title","release","region","hw_id","hw_version","manufacturer"):
                if k in d and d[k]: info[k] = d[k]
        except: pass

    if "model" not in info:
        out, _ = run("cat /tmp/sysinfo/model 2>/dev/null || cat /proc/device-tree/model 2>/dev/null")
        if out: info["model"] = out

    # CPU
    try:
        with open("/proc/cpuinfo") as f:
            cpuinfo = f.read()
            for line in cpuinfo.split("\n"):
                ll = line.lower()
                if any(x in ll for x in ["system type","hardware","machine","model name"]):
                    info["cpu_model"] = line.split(":",1)[1].strip(); break
            info["cpu_count"] = cpuinfo.count("processor\t")
    except: pass

    # Memory
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if "MemTotal" in line: info["ram_total_kb"] = int(line.split()[1])
                elif "MemAvailable" in line: info["ram_free_kb"] = int(line.split()[1])
                elif "MemFree" in line and "ram_free_kb" not in info: info["ram_free_kb"] = int(line.split()[1])
        info["ram_total_mb"] = info.get("ram_total_kb",0) // 1024
        info["ram_used_pct"] = round(100*(1 - info.get("ram_free_kb",1)/max(info.get("ram_total_kb",1),1)),1)
    except: pass

    # Load
    try:
        parts = open("/proc/loadavg").read().split()
        info["load_1m"], info["load_5m"], info["load_15m"] = parts[0], parts[1], parts[2]
    except: pass

    # Uptime
    try:
        sec = float(open("/proc/uptime").read().split()[0])
        info["uptime_s"] = sec
        d,r = divmod(int(sec),86400); h,r = divmod(r,3600); m,_ = divmod(r,60)
        info["uptime_human"] = f"{d}d {h}h {m}m"
    except: pass

    # Disk
    out, _ = run("df -m /opt 2>/dev/null | tail -1")
    if out:
        p = out.split()
        if len(p)>=4: info["disk_total_mb"]=p[1]; info["disk_used_mb"]=p[2]; info["disk_free_mb"]=p[3]

    # Temp
    out, _ = run("cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1")
    if out:
        try: info["temp_c"] = round(int(out)/1000,1)
        except: pass

    info["entware"] = os.path.exists("/opt/bin/opkg")
    return info

# ─── Collection runner ────────────────────────────────────────────────────
def run_collection(report_id, mode, perf):
    """Run all collectors, generate required files, package archive"""
    report_dir = os.path.join(PREFIX, "reports", report_id)
    state_file = os.path.join(PREFIX, "run", "state.json")
    coll_dir = os.path.join(PREFIX, "collectors")
    ts_start = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    events = []

    def evt(eid, data=None):
        e = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "id": eid}
        if data: e["data"] = data
        events.append(e)

    def write_json(name, obj):
        try:
            with open(os.path.join(report_dir, name), "w") as f:
                json.dump(obj, f, indent=2, ensure_ascii=False)
        except: pass

    evt("run.start", {"report_id": report_id, "mode": mode, "perf": perf})

    # ── Preflight ──
    caps = {}
    for cmd in ["ip","ss","iptables","opkg","tar","python3","curl","wget","jq","dmesg","wg","ndmc","iw"]:
        o, rc = run(f"command -v {cmd}", 2); caps[cmd] = rc == 0
    write_json("preflight.json", {"schema_id":"preflight","capabilities":caps,
        "arch":platform.machine(),"entware":os.path.exists("/opt/bin/opkg")})

    # ── Plan ──
    collectors = []
    plan_tasks = []
    if os.path.isdir(coll_dir):
        for d in sorted(os.listdir(coll_dir)):
            if d.startswith("_") or d.startswith("test."): continue
            rs = os.path.join(coll_dir, d, "run.sh")
            pj = os.path.join(coll_dir, d, "plugin.json")
            if not os.path.exists(rs): continue
            timeout = 60
            try:
                with open(pj) as f: meta = json.load(f)
                timeout = meta.get("timeout_s", 60)
            except: meta = {}
            collectors.append((d, rs, timeout))
            plan_tasks.append({"collector_id":d,"status":"INCLUDE","reason":"available","timeout_s":timeout})
    write_json("plan.json", {"schema_id":"plan","tasks":plan_tasks})

    # ── Run collectors ──
    total = len(collectors)
    results_summary = {"ok":0,"skip":0,"fail":0,"timeout":0}
    collector_results = []

    for i, (cid, script, timeout) in enumerate(collectors):
        cwd = os.path.join(report_dir, "collectors", cid)
        os.makedirs(os.path.join(cwd, "artifacts"), exist_ok=True)

        pct = int((i+1) * 100 / max(total, 1))
        try:
            with open(state_file, "w") as f:
                json.dump({"state":"RUNNING","report_id":report_id,"overall_pct":pct,
                    "current_collector":cid,"done":i+1,"total":total}, f)
        except: pass

        evt("collector.start", {"id": cid})
        env = os.environ.copy()
        env.update({"TOOL_BASE_DIR":PREFIX,"COLLECTOR_WORKDIR":cwd,
            "COLLECTOR_ID":cid,"TOOL_REPORT_ID":report_id,
            "RESEARCH_MODE":mode,"PERF_MODE":perf})

        cst = "OK"; t0 = time.time()
        try:
            r = subprocess.run(["sh", script], cwd=cwd, env=env,
                capture_output=True, text=True, timeout=min(timeout, 120))
            with open(os.path.join(cwd, "stdout.log"), "w") as f:
                f.write(r.stdout + "\n" + r.stderr)
            cst = "OK" if r.returncode == 0 else "FAIL"
        except subprocess.TimeoutExpired: cst = "TIMEOUT"
        except: cst = "FAIL"

        dur = round((time.time() - t0) * 1000)
        results_summary["ok" if cst=="OK" else ("timeout" if cst=="TIMEOUT" else "fail")] += 1
        evt("collector.finish", {"id":cid,"status":cst,"duration_ms":dur})

        # Count artifacts
        art_count = 0
        if os.path.isdir(os.path.join(cwd, "artifacts")):
            art_count = len(os.listdir(os.path.join(cwd, "artifacts")))
        collector_results.append({"id":cid,"status":cst,"duration_ms":dur,"artifacts":art_count})

    # ── Device info ──
    write_json("device.json", detect_device())

    # ── Inventory (from sockets + ps data) ──
    inventory_entries = []
    ss_file = os.path.join(report_dir, "collectors", "network.sockets", "artifacts", "ss_tulnp.txt")
    if os.path.exists(ss_file):
        try:
            seen_ports = set()
            with open(ss_file) as f:
                for line in f:
                    if "LISTEN" not in line and "UNCONN" not in line: continue
                    parts = line.split()
                    if len(parts) < 4: continue

                    proto = parts[0]
                    local = ""; proc = ""

                    # Detect format: netstat vs ss
                    # netstat: tcp  0  0  127.0.0.1:80  0.0.0.0:*  LISTEN  1234/nginx
                    # ss:      LISTEN  0  128  127.0.0.1:80  0.0.0.0:*  users:(("nginx",pid=1234,fd=5))
                    if proto in ("tcp","tcp6","udp","udp6"):
                        # netstat format
                        local = parts[3] if len(parts) > 3 else ""
                        # Process: last column like "1234/nginx"
                        for p in parts:
                            if "/" in p and p[0].isdigit():
                                proc = p.split("/",1)[1] if "/" in p else ""
                                break
                    elif parts[0] in ("LISTEN","UNCONN"):
                        # ss format
                        proto = "tcp" if "LISTEN" in line else "udp"
                        local = parts[3] if len(parts) > 3 else ""
                        if "users:" in line:
                            try: proc = line.split('(("')[1].split('"')[0]
                            except: pass
                    else:
                        continue

                    port = local.rsplit(":",1)[-1] if ":" in local else ""
                    bind = local.rsplit(":",1)[0] if ":" in local else ""
                    if not port or not port.isdigit(): continue

                    pk = f"{proto}:{port}"
                    if pk in seen_ports: continue
                    seen_ports.add(pk)

                    warn = []
                    if bind in ("0.0.0.0","::","*","0.0.0.0"): warn.append("external_bind")

                    inventory_entries.append({"port":int(port),"proto":proto,
                        "bind_addr":bind,"process_name":proc,"warnings":warn})
        except: pass
    write_json("inventory.json", {"schema_id":"inventory","schema_version":"1",
        "report_id":report_id,"entries":inventory_entries,
        "statistics":{"total_ports":len(inventory_entries)}})

    # ── Checks (basic) ──
    checks_list = []

    # 1. External bind — only well-known dangerous ports, limit to 10
    ext_count = 0
    for e in inventory_entries:
        if "external_bind" in e.get("warnings",[]) and ext_count < 10:
            checks_list.append({"id":"net.external_bind","severity":"WARN",
                "title":"Port open on all interfaces",
                "evidence":f"port {e['port']} {e['proto']} ({e.get('process_name','?')})",
                "remediation_hint":"Review if this port should be exposed to WAN"})
            ext_count += 1
    if ext_count >= 10:
        checks_list.append({"id":"net.many_external","severity":"WARN",
            "title":f"{sum(1 for e in inventory_entries if 'external_bind' in e.get('warnings',[]))} ports on 0.0.0.0",
            "evidence":"Multiple","remediation_hint":"Review firewall rules"})

    # 2. Dmesg anomalies
    dmesg = os.path.join(report_dir,"collectors","logs.system","artifacts","dmesg.txt")
    if os.path.exists(dmesg):
        try:
            with open(dmesg) as f: dtxt = f.read()
            if "Out of memory" in dtxt or "oom_kill" in dtxt:
                checks_list.append({"id":"logs.oom","severity":"CRIT","title":"OOM killer detected",
                    "evidence":"dmesg","remediation_hint":"Check memory usage, reduce parallel tasks"})
            if "segfault" in dtxt.lower():
                checks_list.append({"id":"logs.segfault","severity":"WARN","title":"Segfault detected",
                    "evidence":"dmesg","remediation_hint":"Check for unstable packages"})
            if "error" in dtxt.lower() and "usb" in dtxt.lower():
                checks_list.append({"id":"logs.usb_error","severity":"WARN","title":"USB errors in dmesg",
                    "evidence":"dmesg","remediation_hint":"Check USB drive health"})
        except: pass

    # 3. Device health
    dev = detect_device()
    if dev.get("ram_used_pct",0) > 85:
        checks_list.append({"id":"res.high_ram","severity":"WARN","title":f"High RAM usage: {dev['ram_used_pct']}%",
            "evidence":f"{dev.get('ram_total_mb',0)}MB total","remediation_hint":"Check for memory leaks"})
    if dev.get("temp_c",0) > 75:
        checks_list.append({"id":"res.high_temp","severity":"WARN","title":f"High temperature: {dev['temp_c']}°C",
            "evidence":"thermal_zone","remediation_hint":"Improve cooling"})
    try:
        load1 = float(dev.get("load_1m",0)); cpus = dev.get("cpu_count",1)
        if load1 > cpus * 2:
            checks_list.append({"id":"res.high_load","severity":"WARN","title":f"High load: {load1} ({cpus} cores)",
                "evidence":"loadavg","remediation_hint":"Check for runaway processes"})
    except: pass
    try:
        dfree = int(dev.get("disk_free_mb",9999))
        if dfree < 100:
            checks_list.append({"id":"res.low_disk","severity":"CRIT" if dfree<50 else "WARN",
                "title":f"Low disk: {dfree}MB free","evidence":"df","remediation_hint":"Clean old reports/logs"})
    except: pass

    # 4. Security checks from firewall
    fw = os.path.join(report_dir,"collectors","network.firewall","artifacts","iptables_save.txt")
    if os.path.exists(fw):
        try:
            with open(fw) as f: fwtxt = f.read()
            if fwtxt.count("\n") < 5:
                checks_list.append({"id":"sec.minimal_firewall","severity":"WARN",
                    "title":"Very few firewall rules","evidence":"iptables","remediation_hint":"Review firewall config"})
        except: pass

    # 5. Check for SSH on default port
    for e in inventory_entries:
        if e["port"] == 22 and "external_bind" in e.get("warnings",[]):
            checks_list.append({"id":"sec.ssh_exposed","severity":"CRIT","title":"SSH on port 22 exposed to all interfaces",
                "evidence":"ss","remediation_hint":"Restrict SSH to LAN only"})

    # 6. Conntrack usage
    ct_max = os.path.join(report_dir,"collectors","network.conntrack","artifacts","conntrack_max.txt")
    ct_count = os.path.join(report_dir,"collectors","network.conntrack","artifacts","conntrack_count.txt")
    if os.path.exists(ct_max) and os.path.exists(ct_count):
        try:
            mx = int(open(ct_max).read().strip())
            cnt = int(open(ct_count).read().strip())
            pct = round(cnt*100/max(mx,1))
            if pct > 70:
                checks_list.append({"id":"net.conntrack_high","severity":"WARN" if pct<90 else "CRIT",
                    "title":f"Conntrack {pct}% full ({cnt}/{mx})","evidence":"conntrack",
                    "remediation_hint":"Increase nf_conntrack_max or check for connection floods"})
        except: pass
    write_json("checks.json", {"schema_id":"checks","schema_version":"1","report_id":report_id,
        "summary":{"total":len(checks_list),"critical":sum(1 for c in checks_list if c["severity"]=="CRIT"),
            "warn":sum(1 for c in checks_list if c["severity"]=="WARN"),
            "info":sum(1 for c in checks_list if c["severity"]=="INFO")},
        "checks":checks_list})

    # ── Redaction report ──
    write_json("redaction_report.json", {"schema_id":"redaction_report","schema_version":"1",
        "research_mode":mode,"masked":mode in ("light","medium"),
        "total_findings":0,"findings":[],"summary":{}})

    # ── Event log ──
    try:
        with open(os.path.join(report_dir, "event_log.jsonl"), "w") as f:
            for e in events: f.write(json.dumps(e, ensure_ascii=False) + "\n")
    except: pass

    # ── Summary ──
    ts_end = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    write_json("summary.json", {"schema_id":"summary","report_id":report_id,
        "mode":mode,"perf":perf,"started_at":ts_start,"finished_at":ts_end,
        "collectors":results_summary,"collector_details":collector_results})

    # ── Manifest ──
    files = []
    for root, dirs, fnames in os.walk(report_dir):
        for fn in fnames:
            fp = os.path.join(root, fn)
            rel = os.path.relpath(fp, report_dir)
            files.append({"path":rel,"size":os.path.getsize(fp)})
    write_json("manifest.json", {"schema_id":"manifest","schema_version":"1",
        "report_id":report_id,"created_at":ts_end,"total_files":len(files),"files":files})

    # ── Archive (tar.gz or zip) ──
    cfg = load_config()
    fmt = cfg.get("archive_format", "tar.gz")
    archive_path = None
    try:
        if fmt == "zip":
            import zipfile
            archive_path = os.path.join(PREFIX, "reports", f"{report_id}.zip")
            with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as zf:
                for root, dirs, fnames in os.walk(report_dir):
                    for fn in fnames:
                        fp = os.path.join(root, fn)
                        arcname = os.path.join(report_id, os.path.relpath(fp, report_dir))
                        zf.write(fp, arcname)
        else:
            import tarfile
            archive_path = os.path.join(PREFIX, "reports", f"{report_id}.tar.gz")
            with tarfile.open(archive_path, "w:gz") as tf:
                tf.add(report_dir, arcname=report_id)
    except Exception as e:
        evt("archive.error", {"error": str(e)})

    # ── Done ──
    try:
        with open(state_file, "w") as f:
            json.dump({"state":"DONE","report_id":report_id,
                "summary":results_summary,"archive":archive_path}, f)
    except: pass

# ─── HTTP Handler ─────────────────────────────────────────────────────────
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(s, *a, **kw): super().__init__(*a, directory=STATIC, **kw)
    def check_auth(s):
        t = load_token()
        if not t: return True
        a = s.headers.get("Authorization","")
        if a == f"Bearer {t}": return True
        if "?" in s.path and f"token={t}" in s.path.split("?",1)[1]: return True
        return False
    def json(s, d, code=200):
        b = json.dumps(d, ensure_ascii=False, indent=2).encode()
        s.send_response(code)
        s.send_header("Content-Type","application/json;charset=utf-8")
        s.send_header("Content-Length",str(len(b)))
        s.send_header("Access-Control-Allow-Origin","*")
        s.send_header("Access-Control-Allow-Headers","Authorization,Content-Type")
        s.end_headers(); s.wfile.write(b)
    def file_json(s, p):
        try:
            with open(p) as f: s.json(json.load(f))
        except: s.json({"error":f"not found: {os.path.basename(p)}"},404)
    def body(s):
        try:
            n = int(s.headers.get("Content-Length",0))
            if n>0: return json.loads(s.rfile.read(n))
        except: pass
        return {}
    def do_OPTIONS(s):
        s.send_response(200)
        for h,v in [("Access-Control-Allow-Origin","*"),("Access-Control-Allow-Methods","GET,POST,OPTIONS"),
                     ("Access-Control-Allow-Headers","Authorization,Content-Type")]:
            s.send_header(h,v)
        s.end_headers()
    def log_message(s,*a): pass

    def do_GET(s):
        p = s.path.split("?")[0]
        if p == "/health":
            v = "?"
            try: v = open(os.path.join(PREFIX,"VERSION")).read().strip()
            except: pass
            s.json({"status":"ok","version":v,"port":PORT}); return
        if not p.startswith("/api/"): super().do_GET(); return
        if not s.check_auth(): s.json({"error":"unauthorized"},401); return

        if p=="/api/progress":
            sf=os.path.join(PREFIX,"run","state.json")
            s.file_json(sf) if os.path.exists(sf) else s.json({"state":"idle"})
        elif p=="/api/device": s.json(detect_device())
        elif p=="/api/config": s.file_json(CONFIG_FILE) if os.path.exists(CONFIG_FILE) else s.json({})
        elif p=="/api/apps": s.json({"apps":detect_app_status()})
        elif p=="/api/reports":
            rd=os.path.join(PREFIX,"reports"); reps=[]
            if os.path.isdir(rd):
                for d in sorted(os.listdir(rd),reverse=True):
                    dp=os.path.join(rd,d)
                    if os.path.isdir(dp):
                        sz=sum(os.path.getsize(os.path.join(dp,f)) for f in os.listdir(dp) if os.path.isfile(os.path.join(dp,f)))
                        reps.append({"id":d,"size_bytes":sz})
            s.json({"reports":reps})
        elif re.match(r"/api/report/[^/]+/(manifest|checks|inventory|redaction|summary|preflight|plan)",p):
            pts=p.split("/"); rid,sub=pts[3],pts[4]
            fmap={"redaction":"redaction_report.json"}
            s.file_json(os.path.join(PREFIX,"reports",rid,fmap.get(sub,sub+".json")))
        elif re.match(r"/api/report/[^/]+/download",p):
            rid=p.split("/")[3]
            # Find archive
            for ext in (".tar.gz",".zip"):
                af=os.path.join(PREFIX,"reports",rid+ext)
                if os.path.exists(af):
                    s.send_response(200)
                    s.send_header("Content-Type","application/octet-stream")
                    s.send_header("Content-Disposition",f"attachment; filename={rid}{ext}")
                    s.send_header("Content-Length",str(os.path.getsize(af)))
                    s.end_headers()
                    with open(af,"rb") as f:
                        while True:
                            chunk=f.read(65536)
                            if not chunk: break
                            s.wfile.write(chunk)
                    return
            s.json({"error":"archive not found"},404)
        elif p.startswith("/api/i18n/"):
            s.file_json(os.path.join(PREFIX,"i18n",p.split("/")[-1]+".json"))
        elif p=="/api/preflight": s.json({"message":"Use POST /api/preflight/run"})
        else: s.json({"error":"not found"},404)

    def do_POST(s):
        p = s.path.split("?")[0]
        if not s.check_auth(): s.json({"error":"unauthorized"},401); return
        b = s.body()

        if p=="/api/start":
            # Use config defaults, override with body params
            cfg = load_config()
            mode=b.get("mode", cfg.get("research_mode","medium"))
            perf=b.get("perf", cfg.get("performance_mode","auto"))
            # Dangerous ops warning
            if cfg.get("dangerous_ops") and not b.get("confirmed"):
                s.json({"warning":"dangerous_ops enabled","need_confirm":True}); return
            rid = f"report-{int(time.time())}"
            rd = os.path.join(PREFIX,"reports",rid)
            os.makedirs(os.path.join(rd,"collectors"),exist_ok=True)
            # Write initial state
            with open(os.path.join(PREFIX,"run","state.json"),"w") as f:
                json.dump({"state":"RUNNING","report_id":rid,"overall_pct":0},f)
            # Run in background thread
            t = threading.Thread(target=run_collection, args=(rid,mode,perf), daemon=True)
            t.start()
            s.json({"status":"started","report_id":rid})

        elif p=="/api/stop":
            with open(os.path.join(PREFIX,"run","state.json"),"w") as f:
                json.dump({"state":"CANCELLED"},f)
            s.json({"status":"cancelled"})

        elif re.match(r"/api/report/[^/]+/delete",p):
            rid=p.split("/")[3]
            import shutil
            rd=os.path.join(PREFIX,"reports",rid)
            if os.path.isdir(rd):
                shutil.rmtree(rd, ignore_errors=True)
                # Also remove archive
                for ext in (".tar.gz",".zip"):
                    af=os.path.join(PREFIX,"reports",rid+ext)
                    if os.path.exists(af): os.remove(af)
                s.json({"status":"deleted","report_id":rid})
            else: s.json({"error":"not found"},404)

        elif p=="/api/config":
            try:
                with open(CONFIG_FILE,"w") as f: json.dump(b,f,indent=2,ensure_ascii=False)
                s.json({"status":"saved"})
            except Exception as e: s.json({"error":str(e)},500)

        elif p=="/api/preflight/run":
            caps={}
            for cmd in ["ip","ss","iptables","opkg","tar","python3","curl","wget","jq","dmesg","wg","ndmc","iw"]:
                out,rc = run(f"command -v {cmd}",2)
                caps[cmd] = rc==0
            warns=[]
            out,_ = run("df -m /opt 2>/dev/null|tail -1|awk '{print $4}'",5)
            free = int(out) if out.isdigit() else 0
            if free<50: warns.append({"severity":"CRIT","msg":f"Мало места: {free}MB / Low disk: {free}MB"})
            elif free<200: warns.append({"severity":"WARN","msg":f"Диск: {free}MB / Disk: {free}MB"})
            out,_=run("awk '/MemAvailable/{print $2}' /proc/meminfo",3)
            ramf=int(out) if out.isdigit() else 0
            if ramf<32768: warns.append({"severity":"WARN","msg":f"Мало RAM: {ramf//1024}MB / Low RAM: {ramf//1024}MB"})
            colls=[]
            cd=os.path.join(PREFIX,"collectors")
            if os.path.isdir(cd):
                for d in sorted(os.listdir(cd)):
                    if d.startswith("_") or d.startswith("test."): continue
                    pj=os.path.join(cd,d,"plugin.json")
                    if os.path.exists(pj):
                        try:
                            m=json.load(open(pj))
                            colls.append({"id":d,"name":m.get("name",d),"status":"INCLUDE","reason":"available","timeout_s":m.get("timeout_s",60)})
                        except: colls.append({"id":d,"name":d,"status":"SKIP","reason":"bad plugin.json"})
            s.json({"capabilities":caps,"warnings":warns,"collectors":colls,"disk_free_mb":free,"ram_free_kb":ramf})

        elif p=="/api/app/install":
            aid=b.get("app_id","")
            app=next((a for a in APPS if a["id"]==aid),None)
            if not app: s.json({"error":"unknown app"},400); return
            output_lines = []
            if app.get("opkg") and app.get("repo_line"):
                # Setup opkg repo
                repo_conf = f"/opt/etc/opkg/{aid}.conf"
                os.makedirs("/opt/etc/opkg", exist_ok=True)
                with open(repo_conf, "w") as rf: rf.write(app["repo_line"] + "\n")
                output_lines.append(f"Repo configured: {repo_conf}")
                # Update
                o,_ = run("opkg update 2>&1", 60)
                output_lines.append(o)
                # Install
                o,rc = run(f"opkg install {app['opkg']} 2>&1", 120)
                output_lines.append(o)
                if rc != 0:
                    output_lines.append(f"ERROR: opkg install returned {rc}")
                s.json({"status":"done" if rc==0 else "error","output":"\n".join(output_lines)})
            elif app.get("install_cmd"):
                o,rc = run(app["install_cmd"] + " 2>&1", 180)
                s.json({"status":"done" if rc==0 else "error","output":o})
            else:
                s.json({"error":"No install method for this app. Install manually."},400)

        elif p=="/api/app/remove":
            aid=b.get("app_id","")
            app=next((a for a in APPS if a["id"]==aid),None)
            if not app: s.json({"error":"unknown"},400); return
            if app.get("opkg"):
                o,_=run(f"opkg remove {app['opkg']} 2>&1",30)
                run(f"rm -f /opt/etc/opkg/{aid}.conf",5)
                s.json({"status":"done","output":o})
            else: s.json({"error":"Manual removal needed"},400)

        elif p=="/api/app/control":
            aid=b.get("app_id",""); act=b.get("action","status")
            # Find service script
            svc=None
            app=next((a for a in APPS if a["id"]==aid),None)
            if app:
                for pat in app.get("svc_glob",[]):
                    for f in glob.glob("/opt/etc/init.d/*"):
                        try:
                            if glob.fnmatch.fnmatch(os.path.basename(f),pat): svc=f; break
                        except: pass
                    if svc: break
            if svc:
                o,_=run(f'"{svc}" {act} 2>&1',15)
                s.json({"status":"done","action":act,"output":o})
            else: s.json({"error":"service not found"},404)

        else: s.json({"error":"not found"},404)

print(f"Keenetic-RDCT WebUI: http://0.0.0.0:{PORT}",flush=True)
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer((BIND,PORT),H) as srv: srv.serve_forever()
