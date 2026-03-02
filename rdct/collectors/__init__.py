from .base import BaseCollector, CollectorMeta

from .device_info import DeviceInfoCollector
from .environment import EnvironmentDetectorCollector
from .storage_mount import StorageMountDfCollector
from .proc_snapshot import ProcSnapshotCollector
from .dmesg import DmesgCollector
from .network_basics import NetworkBasicsCollector
from .routes_rules import RoutesRulesCollector
from .sockets_ports import SocketsPortsCollector
from .keenetic_config import KeeneticConfigCollector
from .ndm_events_hooks import NDMEventsHooksCollector
from .entware_opkg import EntwareOpkgCollector
from .entware_services import EntwareServicesCollector
from .web_discovery import WebDiscoveryCollector
from .sensitive_scanner import SensitiveScannerCollector
from .mirror import MirrorCollector
from .summary import SummaryCollector
from .checksums import ChecksumsCollector
from .diff import DiffCollector


from typing import List, Dict


def default_collectors() -> List[BaseCollector]:
    return [
        DeviceInfoCollector(),
        EnvironmentDetectorCollector(),
        StorageMountDfCollector(),
        ProcSnapshotCollector(),
        DmesgCollector(),
        NetworkBasicsCollector(),
        RoutesRulesCollector(),
        SocketsPortsCollector(),
        KeeneticConfigCollector(),
        NDMEventsHooksCollector(),
        EntwareOpkgCollector(),
        EntwareServicesCollector(),
        WebDiscoveryCollector(),
        SensitiveScannerCollector(),
        MirrorCollector(),
        SummaryCollector(),
        DiffCollector(),
        ChecksumsCollector(),
    ]


def collectors_by_id() -> Dict[str, BaseCollector]:
    return {c.META.collector_id: c for c in default_collectors()}
