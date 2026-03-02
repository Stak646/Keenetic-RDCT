from __future__ import annotations

import json
import mimetypes
import threading
import urllib.parse
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, Optional

from ..config import ConfigManager
from ..core import RDCTCore
from ..storage import build_layout, preflight_usb_only
from ..utils import stable_json_dumps, utc_now_iso


class RDCTService:
    def __init__(self, base_path: Path) -> None:
        self.base_path = base_path
        self.cfg_mgr = ConfigManager(base_path)
        self.cfg = self.cfg_mgr.load_or_create()
        self.layout = build_layout(base_path)
        self.core = RDCTCore(self.layout, self.cfg)

        self._lock = threading.Lock()
        self._run_thread: Optional[threading.Thread] = None
        self._run_result: Optional[Dict[str, Any]] = None
        self._run_error: Optional[str] = None

    def auth_token(self) -> str:
        return str(self.cfg.get("server", {}).get("token") or "")

    def reload_config(self) -> None:
        self.cfg = self.cfg_mgr.load_or_create()
        self.core = RDCTCore(self.layout, self.cfg)

    def status(self) -> Dict[str, Any]:
        with self._lock:
            running = bool(self._run_thread and self._run_thread.is_alive())
            return {
                "time": utc_now_iso(),
                "running": running,
                "run_result": self._run_result,
                "run_error": self._run_error,
            }

    def start_run(self, mode: Optional[str], perf: Optional[str], baseline: bool, initiator: str = "webui") -> Dict[str, Any]:
        with self._lock:
            if self._run_thread and self._run_thread.is_alive():
                return {"ok": False, "error": "Run already in progress"}
            self._run_result = None
            self._run_error = None

            # fresh core with latest config
            self.reload_config()

            def target():
                try:
                    rr = self.core.run(initiator=initiator, requested_mode=mode, requested_perf=perf, force_baseline=baseline)
                    with self._lock:
                        self._run_result = {
                            "run_id": rr.run_id,
                            "status": rr.status,
                            "snapshot_path": str(rr.snapshot_path),
                            "archive_path": str(rr.archive_path) if rr.archive_path else None,
                            "manifest_path": str(rr.manifest_path),
                        }
                except Exception as e:
                    with self._lock:
                        self._run_error = str(e)

            self._run_thread = threading.Thread(target=target, daemon=True)
            self._run_thread.start()
            return {"ok": True}

    def stop_run(self) -> Dict[str, Any]:
        with self._lock:
            if not (self._run_thread and self._run_thread.is_alive()):
                return {"ok": False, "error": "No running job"}
            self.core.request_stop()
            return {"ok": True}

    def list_reports(self) -> Dict[str, Any]:
        reports_dir = self.layout.reports_dir
        items = []
        if reports_dir.exists():
            for d in sorted(reports_dir.iterdir(), reverse=True):
                if not d.is_dir():
                    continue
                run_id = d.name
                snap = d / "snapshot"
                manifest = snap / "manifest.json"
                archive = d / f"{run_id}.tar.gz"
                items.append({
                    "run_id": run_id,
                    "has_snapshot": snap.exists(),
                    "has_manifest": manifest.exists(),
                    "archive": archive.exists(),
                    "archive_path": str(archive) if archive.exists() else None,
                })
        return {"count": len(items), "items": items}

    def read_manifest(self, run_id: str) -> Optional[Dict[str, Any]]:
        manifest = self.layout.reports_dir / run_id / "snapshot" / "manifest.json"
        if not manifest.exists():
            return None
        return json.loads(manifest.read_text(encoding="utf-8"))

    def read_file(self, run_id: str, rel_path: str) -> Optional[Path]:
        # Strictly within snapshot directory
        snap = (self.layout.reports_dir / run_id / "snapshot").resolve()
        p = (snap / rel_path).resolve()
        try:
            p.relative_to(snap)
        except Exception:
            return None
        if not p.exists():
            return None
        return p


class RDCTHandler(BaseHTTPRequestHandler):
    server_version = "RDCTHTTP/1.0"

    def do_GET(self) -> None:
        svc: RDCTService = self.server.svc  # type: ignore
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path.startswith("/api/"):
            if not self._check_auth(svc):
                self._json({"ok": False, "error": "unauthorized"}, status=HTTPStatus.UNAUTHORIZED)
                return

        if path == "/api/v1/status":
            self._json({"ok": True, "status": svc.status()})
            return
        if path == "/api/v1/reports":
            self._json({"ok": True, "reports": svc.list_reports()})
            return
        if path.startswith("/api/v1/reports/") and path.endswith("/manifest"):
            run_id = path.split("/")[4]
            m = svc.read_manifest(run_id)
            if m is None:
                self._json({"ok": False, "error": "not_found"}, status=HTTPStatus.NOT_FOUND)
                return
            self._json({"ok": True, "manifest": m})
            return
        if path.startswith("/api/v1/reports/") and path.endswith("/download"):
            run_id = path.split("/")[4]
            archive = svc.layout.reports_dir / run_id / f"{run_id}.tar.gz"
            if not archive.exists():
                self._json({"ok": False, "error": "archive_not_found"}, status=HTTPStatus.NOT_FOUND)
                return
            self._send_file(archive, content_type="application/gzip")
            return
        if path.startswith("/api/v1/reports/") and "/file/" in path:
            # /api/v1/reports/<run_id>/file/<rel_path...>
            parts = path.split("/", 6)
            if len(parts) < 7:
                self._json({"ok": False, "error": "bad_request"}, status=HTTPStatus.BAD_REQUEST)
                return
            run_id = parts[4]
            rel = parts[6]
            fpath = svc.read_file(run_id, rel)
            if not fpath:
                self._json({"ok": False, "error": "not_found"}, status=HTTPStatus.NOT_FOUND)
                return
            ctype, _ = mimetypes.guess_type(str(fpath))
            self._send_file(fpath, content_type=ctype or "application/octet-stream")
            return

        # Static UI
        if path == "/":
            path = "/index.html"
        static_root = Path(__file__).parent / "static"
        fpath = (static_root / path.lstrip("/")).resolve()
        try:
            fpath.relative_to(static_root.resolve())
        except Exception:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        if not fpath.exists() or fpath.is_dir():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        ctype, _ = mimetypes.guess_type(str(fpath))
        self._send_file(fpath, content_type=ctype or "text/plain")
        return

    def do_POST(self) -> None:
        svc: RDCTService = self.server.svc  # type: ignore
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        if path.startswith("/api/"):
            if not self._check_auth(svc):
                self._json({"ok": False, "error": "unauthorized"}, status=HTTPStatus.UNAUTHORIZED)
                return

        length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(length) if length else b""
        payload = {}
        if body:
            try:
                payload = json.loads(body.decode("utf-8", errors="ignore"))
            except Exception:
                payload = {}

        if path == "/api/v1/run/start":
            mode = payload.get("research_mode")
            perf = payload.get("performance_mode")
            baseline = bool(payload.get("baseline", False))
            self._json(svc.start_run(mode, perf, baseline))
            return
        if path == "/api/v1/run/stop":
            self._json(svc.stop_run())
            return
        if path == "/api/v1/config":
            # Update config (best-effort, safe subset)
            cfg = svc.cfg_mgr.load_or_create()
            for k, v in (payload.get("set") or {}).items():
                # dotted keys allowed
                _set_dotted(cfg, k, v)
            svc.cfg_mgr.save(cfg)
            svc.reload_config()
            self._json({"ok": True})
            return

        self._json({"ok": False, "error": "not_found"}, status=HTTPStatus.NOT_FOUND)

    def log_message(self, format: str, *args: Any) -> None:
        # silence default stdout logging
        return

    def _check_auth(self, svc: RDCTService) -> bool:
        token = svc.auth_token()
        if not token:
            return True
        hdr = self.headers.get("X-RDCT-Token") or ""
        if not hdr:
            auth = self.headers.get("Authorization") or ""
            if auth.lower().startswith("bearer "):
                hdr = auth.split(" ", 1)[1].strip()
        return hdr == token

    def _json(self, obj: Dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        data = stable_json_dumps(obj).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _send_file(self, path: Path, content_type: str) -> None:
        data = path.read_bytes()
        self.send_response(HTTPStatus.OK.value)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def _set_dotted(cfg: Dict[str, Any], dotted_key: str, value: Any) -> None:
    cur = cfg
    parts = dotted_key.split(".")
    for k in parts[:-1]:
        if k not in cur or not isinstance(cur[k], dict):
            cur[k] = {}
        cur = cur[k]
    cur[parts[-1]] = value


class RDCTHTTPServer(ThreadingHTTPServer):
    def __init__(self, server_address, RequestHandlerClass, svc: RDCTService):
        super().__init__(server_address, RequestHandlerClass)
        self.svc = svc


def serve(base_path: Path, bind: str, port: int) -> int:
    svc = RDCTService(base_path)
    # Preflight once to fail fast if not on USB
    preflight_usb_only(svc.layout)

    httpd = RDCTHTTPServer((bind, port), RDCTHandler, svc=svc)
    sa = httpd.socket.getsockname()
    actual_port = sa[1]
    svc.core.logger.info(f"WebUI/API started on http://{bind}:{actual_port}/ (token required for /api/*)")
    try:
        httpd.serve_forever()
    finally:
        httpd.server_close()
    return 0
