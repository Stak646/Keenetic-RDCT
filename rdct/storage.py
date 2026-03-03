from __future__ import annotations

import dataclasses
import os
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from .utils import human_bytes


@dataclasses.dataclass(frozen=True)
class MountInfo:
    device: str
    mountpoint: str
    fstype: str
    options: List[str]


_EXTERNAL_DEV_RE = re.compile(r"^/dev/(sd[a-z]\d*|mmcblk\d+p?\d*|nvme\d+n\d+p?\d*|usb\w+\d*)$")


def read_proc_mounts(path: str = "/proc/mounts") -> List[MountInfo]:
    mounts: List[MountInfo] = []
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) < 4:
                    continue
                device, mountpoint, fstype, opts = parts[0], parts[1], parts[2], parts[3]
                mounts.append(MountInfo(device=device, mountpoint=mountpoint, fstype=fstype, options=opts.split(",")))
    except FileNotFoundError:
        return mounts
    return mounts


def is_virtual_fs(mi: MountInfo) -> bool:
    return mi.fstype in {"proc", "sysfs", "devtmpfs", "tmpfs", "overlay", "squashfs", "ramfs", "cgroup", "cgroup2"}


def is_external_device(mi: MountInfo) -> bool:
    # Best-effort heuristic for Keenetic/Entware environments.
    if mi.device.startswith("/dev/") and _EXTERNAL_DEV_RE.match(mi.device):
        return True
    # some systems show UUID=...; treat as external only if mountpoint looks like USB mounts
    if mi.device.startswith("UUID=") and ("/mnt" in mi.mountpoint or "/media" in mi.mountpoint or "/tmp/mnt" in mi.mountpoint):
        return True
    return False


def detect_usb_mounts() -> List[MountInfo]:
    mounts = read_proc_mounts()
    usb: List[MountInfo] = []
    for mi in mounts:
        if is_virtual_fs(mi):
            continue
        if is_external_device(mi):
            usb.append(mi)
    # prefer deeper mountpoints (e.g., /tmp/mnt/sda1) over shallow ones
    usb.sort(key=lambda m: len(m.mountpoint), reverse=True)
    return usb


def find_mount_for_path(path: Path, mounts: List[MountInfo]) -> Optional[MountInfo]:
    p = str(path.resolve())
    best: Optional[MountInfo] = None
    best_len = -1
    for mi in mounts:
        mp = mi.mountpoint.rstrip("/")
        if mp == "":
            mp = "/"
        if p == mp or p.startswith(mp + "/"):
            if len(mp) > best_len:
                best = mi
                best_len = len(mp)
    return best


def statvfs_bytes(path: Path) -> Tuple[int, int]:
    st = os.statvfs(str(path))
    free = st.f_bavail * st.f_frsize
    total = st.f_blocks * st.f_frsize
    return free, total


@dataclasses.dataclass
class StorageLayout:
    base_path: Path
    install_dir: Path
    config_dir: Path
    deps_dir: Path
    cache_dir: Path
    run_dir: Path
    reports_dir: Path
    logs_dir: Path
    apps_dir: Path

    filesystem_type: Optional[str] = None
    mount_flags: Optional[List[str]] = None
    usb_mountpoint: Optional[str] = None
    usb_device: Optional[str] = None
    free_space_before_bytes: Optional[int] = None
    free_space_after_bytes: Optional[int] = None

    def as_dict(self) -> Dict[str, object]:
        return {
            "usb_only_enforced": True,
            "base_path": str(self.base_path),
            "install_dir": str(self.install_dir),
            "config_dir": str(self.config_dir),
            "deps_dir": str(self.deps_dir),
            "cache_dir": str(self.cache_dir),
            "run_dir": str(self.run_dir),
            "reports_dir": str(self.reports_dir),
            "logs_dir": str(self.logs_dir),
            "apps_dir": str(self.apps_dir),
            "free_space_before_bytes": int(self.free_space_before_bytes or 0),
            "free_space_after_bytes": int(self.free_space_after_bytes or 0) if self.free_space_after_bytes is not None else None,
            "filesystem": {
                "type": self.filesystem_type or "unknown",
                "mount_flags": self.mount_flags or [],
            },
        }


class UsbOnlyError(RuntimeError):
    pass


def build_layout(base_path: Path) -> StorageLayout:
    base_path = base_path.resolve()
    return StorageLayout(
        base_path=base_path,
        # Keep tool files separate from data/config to simplify mirroring exclusions and upgrades.
        # The installer places the RDCT package into <base>/install.
        install_dir=base_path / "install",
        config_dir=base_path / "config",
        deps_dir=base_path / "deps",
        cache_dir=base_path / "cache",
        run_dir=base_path / "run",
        reports_dir=base_path / "reports",
        logs_dir=base_path / "logs",
        apps_dir=base_path / "apps",
    )


def preflight_usb_only(layout: StorageLayout) -> StorageLayout:
    """
    Enforce USB-only:
      - detect USB mount
      - ensure all RDCT directories are on USB mount
      - ensure RW and enough free space (best-effort)
    """
    usb_mounts = detect_usb_mounts()
    if not usb_mounts:
        raise UsbOnlyError("USB-only enforced: no external USB mount detected (check /proc/mounts).")

    base_mi = find_mount_for_path(layout.base_path, usb_mounts)
    if not base_mi:
        # base path not on a detected external mount => refuse
        raise UsbOnlyError(f"USB-only enforced: base_path is not on an external USB mount: {layout.base_path}")

    # Make sure directories are on same external mount
    for p in [layout.install_dir, layout.deps_dir, layout.cache_dir, layout.run_dir, layout.reports_dir, layout.logs_dir, layout.config_dir, layout.apps_dir]:
        mi = find_mount_for_path(p, usb_mounts)
        if not mi or mi.mountpoint != base_mi.mountpoint:
            raise UsbOnlyError(
                "USB-only enforced: all RDCT directories must be on the same USB mount. "
                f"Path {p} is not on {base_mi.mountpoint}."
            )

    # Ensure directories exist and writable (install_dir is included for completeness).
    for p in [layout.install_dir, layout.deps_dir, layout.cache_dir, layout.run_dir, layout.reports_dir, layout.logs_dir, layout.config_dir, layout.apps_dir]:
        p.mkdir(parents=True, exist_ok=True)
        testfile = p / ".rdct_rw_test"
        try:
            testfile.write_text("ok", encoding="utf-8")
            testfile.unlink(missing_ok=True)  # py3.8? ok in 3.8? missing_ok since 3.8? yes.
        except Exception as e:
            raise UsbOnlyError(f"USB-only enforced: path not writable on USB: {p} ({e})")

    free, total = statvfs_bytes(layout.base_path)
    layout.usb_mountpoint = base_mi.mountpoint
    layout.usb_device = base_mi.device
    layout.filesystem_type = base_mi.fstype
    layout.mount_flags = base_mi.options
    layout.free_space_before_bytes = free
    return layout


def usb_health_summary(layout: StorageLayout) -> str:
    free = int(layout.free_space_before_bytes or 0)
    ro = "ro" in (layout.mount_flags or [])
    return (
        f"USB mount: {layout.usb_device} on {layout.usb_mountpoint} "
        f"(fs={layout.filesystem_type}, free={human_bytes(free)}, ro={ro})"
    )


def estimate_report_size_bytes(*, research_mode: str, mirror_enabled: bool) -> int:
    """Very rough dry-run estimate of report size.

    This is intentionally conservative and used only for preflight warnings.
    """
    rm = (research_mode or "light").lower()
    base = {
        "light": 25 * 1024 * 1024,
        "medium": 80 * 1024 * 1024,
        "full": 180 * 1024 * 1024,
        "extreme": 300 * 1024 * 1024,
    }.get(rm, 80 * 1024 * 1024)
    if mirror_enabled:
        base += 200 * 1024 * 1024
    return int(base)
