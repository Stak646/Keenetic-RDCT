from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from ..utils import sha256_file, utc_now_iso, write_json


class AppManagerError(RuntimeError):
    pass


@dataclass
class AppStatus:
    app_id: str
    name: str
    installed: bool
    installed_via: Optional[str]
    opkg_installed: bool
    opkg_version: Optional[str]
    last_action: Optional[str]
    last_action_at: Optional[str]


def _run(cmd: List[str], *, timeout: int = 120) -> Tuple[int, str, str]:
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        out, err = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        p.kill()
        out, err = p.communicate()
        return 124, out, err
    return int(p.returncode), out, err


def _read_proc_mounts() -> List[Tuple[str, str, str, str]]:
    rows = []
    try:
        for line in Path('/proc/mounts').read_text(encoding='utf-8', errors='ignore').splitlines():
            parts = line.split()
            if len(parts) >= 4:
                rows.append((parts[0], parts[1], parts[2], parts[3]))
    except Exception:
        pass
    return rows


def _is_external_device(dev: str) -> bool:
    # Best-effort: sdX/mmcblk/nvme or UUID-based mounts on /tmp/mnt.
    return bool(re.match(r'^/dev/(sd[a-z][0-9]*|mmcblk\d+p?\d*|nvme\d+n\d+p?\d*)$', dev))


def ensure_opt_on_usb() -> None:
    mounts = _read_proc_mounts()
    for dev, mp, fstype, opts in mounts:
        if mp == '/opt':
            if 'ro' in opts.split(','):
                raise AppManagerError('/opt is mounted read-only')
            if _is_external_device(dev) or (dev.startswith('UUID=') and mp.startswith('/opt')):
                return
            raise AppManagerError(f'/opt is not on an external device (device={dev})')
    raise AppManagerError('/opt is not mounted. Entware is required for App Manager operations.')


def find_opkg() -> Optional[str]:
    for p in ('/opt/bin/opkg', '/opt/sbin/opkg', 'opkg'):
        if shutil.which(p):
            return shutil.which(p)
    return None


def get_opkg_arch(opkg_path: str) -> Optional[str]:
    rc, out, err = _run([opkg_path, 'print-architecture'], timeout=30)
    if rc != 0:
        return None
    arch_rows: List[Tuple[str, int]] = []
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith('arch '):
            continue
        parts = line.split()
        if len(parts) >= 3:
            name = parts[1]
            try:
                pr = int(parts[2])
            except Exception:
                pr = 0
            if name != 'all':
                arch_rows.append((name, pr))
    if not arch_rows:
        return None
    # highest priority wins
    arch_rows.sort(key=lambda x: x[1], reverse=True)
    return arch_rows[0][0]


def opkg_list_installed(opkg_path: str) -> Dict[str, str]:
    rc, out, err = _run([opkg_path, 'list-installed'], timeout=120)
    if rc != 0:
        return {}
    pkgs: Dict[str, str] = {}
    for line in out.splitlines():
        # format: name - version
        if ' - ' in line:
            name, ver = line.split(' - ', 1)
            pkgs[name.strip()] = ver.strip()
    return pkgs


def _fetch_url_to_file(url: str, dst: Path, *, timeout: int = 120) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    # Prefer curl/wget if available (router environments often lack full CA bundle for python)
    if shutil.which('curl'):
        rc, out, err = _run(['curl', '-fsSL', url, '-o', str(dst)], timeout=timeout)
        if rc != 0:
            raise AppManagerError(f'curl download failed (rc={rc}): {err.strip() or url}')
        return
    if shutil.which('wget'):
        rc, out, err = _run(['wget', '-qO', str(dst), url], timeout=timeout)
        if rc != 0:
            raise AppManagerError(f'wget download failed (rc={rc}): {err.strip() or url}')
        return
    # Python fallback
    import urllib.request

    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            dst.write_bytes(r.read())
    except Exception as e:
        raise AppManagerError(f'Failed to download {url}: {e}')


def _github_latest_release(owner: str, repo: str) -> Dict[str, Any]:
    url = f'https://api.github.com/repos/{owner}/{repo}/releases/latest'
    tmp = Path('/tmp') / f'rdct_gh_{owner}_{repo}_{int(time.time())}.json'
    _fetch_url_to_file(url, tmp, timeout=60)
    try:
        return json.loads(tmp.read_text(encoding='utf-8'))
    finally:
        try:
            tmp.unlink(missing_ok=True)
        except Exception:
            pass


class AppManager:
    """Allowlist App Manager.

    NOTE: installs are explicit user actions (CLI/API), require network access.
    """

    def __init__(self, base_path: Path):
        self.base_path = base_path
        self.apps_root = base_path / 'apps'
        self.catalog_path = Path(__file__).parent / 'catalog.json'

    def load_catalog(self) -> List[Dict[str, Any]]:
        obj = json.loads(self.catalog_path.read_text(encoding='utf-8'))
        apps = obj.get('apps')
        if not isinstance(apps, list):
            return []
        out: List[Dict[str, Any]] = []
        for a in apps:
            if isinstance(a, dict) and a.get('app_id'):
                out.append(a)
        return out

    def _app_state_path(self, app_id: str) -> Path:
        return self.apps_root / app_id / 'state.json'

    def _load_state(self, app_id: str) -> Dict[str, Any]:
        p = self._app_state_path(app_id)
        try:
            if p.exists():
                return json.loads(p.read_text(encoding='utf-8'))
        except Exception:
            return {}
        return {}

    def _save_state(self, app_id: str, state: Dict[str, Any]) -> None:
        p = self._app_state_path(app_id)
        p.parent.mkdir(parents=True, exist_ok=True)
        write_json(p, state)

    def list_status(self) -> List[AppStatus]:
        opkg = find_opkg()
        pkgs = opkg_list_installed(opkg) if opkg else {}

        statuses: List[AppStatus] = []
        for a in self.load_catalog():
            app_id = str(a['app_id'])
            st = self._load_state(app_id)
            pkg_names = (a.get('detect') or {}).get('opkg_packages') or []
            opkg_installed = any(p in pkgs for p in pkg_names) if isinstance(pkg_names, list) else False
            opkg_ver = None
            for p in (pkg_names if isinstance(pkg_names, list) else []):
                if p in pkgs:
                    opkg_ver = pkgs[p]
                    break

            statuses.append(
                AppStatus(
                    app_id=app_id,
                    name=str(a.get('name') or app_id),
                    installed=bool(opkg_installed or st.get('installed')),
                    installed_via=st.get('installed_via'),
                    opkg_installed=bool(opkg_installed),
                    opkg_version=opkg_ver,
                    last_action=st.get('last_action'),
                    last_action_at=st.get('last_action_at'),
                )
            )
        return statuses

    def _require_opkg(self) -> str:
        ensure_opt_on_usb()
        opkg = find_opkg()
        if not opkg:
            raise AppManagerError('opkg not found (Entware required)')
        return opkg

    def install(self, app_id: str) -> Dict[str, Any]:
        app = next((a for a in self.load_catalog() if str(a.get('app_id')) == app_id), None)
        if not app:
            raise AppManagerError(f'Unknown app_id: {app_id}')

        install = app.get('install') or {}
        if not isinstance(install, dict):
            raise AppManagerError('Invalid catalog: install section is not a dict')

        opkg = self._require_opkg()

        kind = str(install.get('type') or '')
        if kind == 'opkg_feed':
            self._install_opkg_feed(opkg, install)
        elif kind == 'opkg_feed_arch':
            self._install_opkg_feed_arch(opkg, install)
        elif kind == 'opkg_custom_feed_append':
            self._install_opkg_custom_feed_append(opkg, install)
        elif kind == 'github_release_ipk':
            self._install_github_release_ipk(opkg, app, install)
        elif kind == 'github_release_ipk_arch':
            self._install_github_release_ipk_arch(opkg, app, install)
        else:
            raise AppManagerError(f'Unsupported install type: {kind}')

        st = self._load_state(app_id)
        st['installed'] = True
        st['installed_via'] = kind
        st['last_action'] = 'install'
        st['last_action_at'] = utc_now_iso()
        self._save_state(app_id, st)

        return {
            'app_id': app_id,
            'status': 'installed',
            'installed_via': kind,
            'time': st['last_action_at'],
        }

    def update(self, app_id: str) -> Dict[str, Any]:
        # For opkg-backed installs, update == upgrade
        app = next((a for a in self.load_catalog() if str(a.get('app_id')) == app_id), None)
        if not app:
            raise AppManagerError(f'Unknown app_id: {app_id}')
        install = app.get('install') or {}
        kind = str((install if isinstance(install, dict) else {}).get('type') or '')

        opkg = self._require_opkg()
        rc, out, err = _run([opkg, 'update'], timeout=180)
        if rc != 0:
            raise AppManagerError(f'opkg update failed: {err.strip()}')

        pkg = str((install if isinstance(install, dict) else {}).get('opkg_package') or app_id)
        rc, out, err = _run([opkg, 'upgrade', pkg], timeout=300)
        if rc != 0:
            # Some opkg versions do not support upgrade for not-installed packages
            rc2, out2, err2 = _run([opkg, 'install', pkg], timeout=300)
            if rc2 != 0:
                msg = (err or '').strip() + ' ' + (err2 or '').strip()
                raise AppManagerError(f'opkg upgrade/install failed: {msg.strip()}')

        st = self._load_state(app_id)
        st['installed'] = True
        st['installed_via'] = st.get('installed_via') or kind
        st['last_action'] = 'update'
        st['last_action_at'] = utc_now_iso()
        self._save_state(app_id, st)

        return {'app_id': app_id, 'status': 'updated', 'time': st['last_action_at']}

    # ---- install helpers ----

    def _install_opkg_feed(self, opkg: str, install: Dict[str, Any]) -> None:
        feed_file = Path(str(install.get('feed_file') or ''))
        feed_line = str(install.get('feed_line') or '')
        pkg = str(install.get('opkg_package') or '')
        if not feed_file or not feed_line or not pkg:
            raise AppManagerError('Catalog entry missing feed_file/feed_line/opkg_package')
        feed_file.parent.mkdir(parents=True, exist_ok=True)
        feed_file.write_text(feed_line.strip() + '\n', encoding='utf-8')

        rc, out, err = _run([opkg, 'update'], timeout=180)
        if rc != 0:
            raise AppManagerError(f'opkg update failed: {err.strip()}')
        rc, out, err = _run([opkg, 'install', pkg], timeout=300)
        if rc != 0:
            # fallback to upgrade
            rc2, out2, err2 = _run([opkg, 'upgrade', pkg], timeout=300)
            if rc2 != 0:
                msg = (err or '').strip() + ' ' + (err2 or '').strip()
                raise AppManagerError(f'opkg install/upgrade failed: {msg.strip()}')

    def _install_opkg_feed_arch(self, opkg: str, install: Dict[str, Any]) -> None:
        arch = get_opkg_arch(opkg)
        if not arch:
            raise AppManagerError('Cannot determine Entware architecture via opkg')
        base_url = str(install.get('base_url') or '').rstrip('/')
        feed_name = str(install.get('feed_name') or 'custom')
        feed_file = Path(str(install.get('feed_file') or ''))
        pkg = str(install.get('opkg_package') or '')
        arch_map = install.get('arch_map') or {}
        if not isinstance(arch_map, dict) or arch not in arch_map:
            raise AppManagerError(f'No arch_map entry for arch={arch}')
        feed_path = str(arch_map[arch]).strip('/')

        line = f"src/gz {feed_name} {base_url}/{feed_path}"
        feed_file.parent.mkdir(parents=True, exist_ok=True)
        feed_file.write_text(line + '\n', encoding='utf-8')

        rc, out, err = _run([opkg, 'update'], timeout=180)
        if rc != 0:
            raise AppManagerError(f'opkg update failed: {err.strip()}')
        rc, out, err = _run([opkg, 'install', pkg], timeout=300)
        if rc != 0:
            rc2, out2, err2 = _run([opkg, 'upgrade', pkg], timeout=300)
            if rc2 != 0:
                msg = (err or '').strip() + ' ' + (err2 or '').strip()
                raise AppManagerError(f'opkg install/upgrade failed: {msg.strip()}')

    def _install_opkg_custom_feed_append(self, opkg: str, install: Dict[str, Any]) -> None:
        arch = get_opkg_arch(opkg)
        if not arch:
            raise AppManagerError('Cannot determine Entware architecture via opkg')
        base_url = str(install.get('base_url') or '').rstrip('/')
        feed_name = str(install.get('feed_name') or 'custom')
        feed_file = Path(str(install.get('feed_file') or ''))
        pkg = str(install.get('opkg_package') or '')
        arch_map = install.get('arch_map') or {}
        if not isinstance(arch_map, dict) or arch not in arch_map:
            raise AppManagerError(f'No arch_map entry for arch={arch}')
        feed_path = str(arch_map[arch]).strip('/')
        line = f"src/gz {feed_name} {base_url}/{feed_path}"

        feed_file.parent.mkdir(parents=True, exist_ok=True)
        current = feed_file.read_text(encoding='utf-8', errors='ignore') if feed_file.exists() else ''
        if line not in current:
            with feed_file.open('a', encoding='utf-8') as f:
                if current and not current.endswith('\n'):
                    f.write('\n')
                f.write(line + '\n')

        rc, out, err = _run([opkg, 'update'], timeout=180)
        if rc != 0:
            raise AppManagerError(f'opkg update failed: {err.strip()}')
        rc, out, err = _run([opkg, 'install', pkg], timeout=300)
        if rc != 0:
            rc2, out2, err2 = _run([opkg, 'upgrade', pkg], timeout=300)
            if rc2 != 0:
                msg = (err or '').strip() + ' ' + (err2 or '').strip()
                raise AppManagerError(f'opkg install/upgrade failed: {msg.strip()}')

    def _install_github_release_ipk(self, opkg: str, app: Dict[str, Any], install: Dict[str, Any]) -> None:
        gh = app.get('github') or {}
        owner = str((gh if isinstance(gh, dict) else {}).get('owner') or '')
        repo = str((gh if isinstance(gh, dict) else {}).get('repo') or '')
        if not owner or not repo:
            raise AppManagerError('Catalog entry missing github.owner/repo')
        asset_re = re.compile(str(install.get('asset_regex') or ''))
        pkg = str(install.get('opkg_package') or '')
        if not asset_re.pattern or not pkg:
            raise AppManagerError('Catalog entry missing asset_regex/opkg_package')

        rel = _github_latest_release(owner, repo)
        tag = str(rel.get('tag_name') or rel.get('name') or 'latest')
        assets = rel.get('assets') or []
        if not isinstance(assets, list):
            raise AppManagerError('GitHub API response missing assets')

        chosen = None
        for a in assets:
            if isinstance(a, dict) and a.get('name') and a.get('browser_download_url'):
                n = str(a['name'])
                if asset_re.search(n):
                    chosen = a
                    break
        if not chosen:
            raise AppManagerError(f'No release asset matched: {asset_re.pattern}')

        url = str(chosen['browser_download_url'])
        name = str(chosen['name'])

        dl_dir = self.apps_root / str(app.get('app_id') or repo) / 'downloads' / tag
        ipk_path = dl_dir / name
        _fetch_url_to_file(url, ipk_path)

        sha = sha256_file(ipk_path)
        meta = {'downloaded_at': utc_now_iso(), 'tag': tag, 'asset': name, 'sha256': sha, 'url': url}
        write_json(dl_dir / 'download.json', meta)

        rc, out, err = _run([opkg, 'install', str(ipk_path)], timeout=300)
        if rc != 0:
            # try upgrade with local file (some opkg don't)
            raise AppManagerError(f'opkg install ipk failed: {err.strip()}')

    def _install_github_release_ipk_arch(self, opkg: str, app: Dict[str, Any], install: Dict[str, Any]) -> None:
        gh = app.get('github') or {}
        owner = str((gh if isinstance(gh, dict) else {}).get('owner') or '')
        repo = str((gh if isinstance(gh, dict) else {}).get('repo') or '')
        if not owner or not repo:
            raise AppManagerError('Catalog entry missing github.owner/repo')

        arch = get_opkg_arch(opkg)
        if not arch:
            raise AppManagerError('Cannot determine Entware architecture via opkg')

        tpl = str(install.get('asset_template') or '')
        if '{arch}' not in tpl:
            raise AppManagerError('asset_template must contain {arch}')

        prefer_kn = bool(install.get('prefer_kn_variant', False))
        patterns = []
        if prefer_kn:
            patterns.append(tpl.format(arch=f"{arch}_kn"))
        patterns.append(tpl.format(arch=arch))

        rel = _github_latest_release(owner, repo)
        tag = str(rel.get('tag_name') or rel.get('name') or 'latest')
        assets = rel.get('assets') or []
        if not isinstance(assets, list):
            raise AppManagerError('GitHub API response missing assets')

        chosen = None
        chosen_pat = None
        for pat in patterns:
            rx = re.compile(pat)
            for a in assets:
                if isinstance(a, dict) and a.get('name') and a.get('browser_download_url'):
                    n = str(a['name'])
                    if rx.search(n):
                        chosen = a
                        chosen_pat = pat
                        break
            if chosen:
                break

        if not chosen:
            raise AppManagerError(f'No release asset matched arch={arch} patterns={patterns}')

        url = str(chosen['browser_download_url'])
        name = str(chosen['name'])

        dl_dir = self.apps_root / str(app.get('app_id') or repo) / 'downloads' / tag
        ipk_path = dl_dir / name
        _fetch_url_to_file(url, ipk_path)

        sha = sha256_file(ipk_path)
        meta = {'downloaded_at': utc_now_iso(), 'tag': tag, 'asset': name, 'sha256': sha, 'url': url, 'pattern': chosen_pat, 'arch': arch}
        write_json(dl_dir / 'download.json', meta)

        rc, out, err = _run([opkg, 'install', str(ipk_path)], timeout=300)
        if rc != 0:
            raise AppManagerError(f'opkg install ipk failed: {err.strip()}')
