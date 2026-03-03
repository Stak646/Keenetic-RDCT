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

# Extended collectors (opt-in via policy/config)
from .firewall import FirewallCollector
from .conntrack import ConntrackCollector
from .dns import DNSCollector
from .dhcp import DHCPCollector
from .wifi import WiFiCollector
from .vpn import VPNCollector
from .file_security import FileSecurityInventoryCollector
from .recent_changes import RecentChangesCollector
from .large_files import LargeFilesCollector
from .app_inventory import AppInventoryCollector
from .app_debug_bundles import AppDebugBundlesCollector
from .allowlist_apps import AllowlistAppsCollector
from .timeline import TimelineCollector
from .performance_profile import PerformanceProfileCollector
from .sandbox_tests import SandboxTestsCollector
from .js_api_extractor import JSApiExtractorCollector


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

        # Extended
        FirewallCollector(),
        ConntrackCollector(),
        DNSCollector(),
        DHCPCollector(),
        WiFiCollector(),
        VPNCollector(),
        FileSecurityInventoryCollector(),
        RecentChangesCollector(),
        LargeFilesCollector(),
        AppInventoryCollector(),
        AppDebugBundlesCollector(),
        AllowlistAppsCollector(),
        TimelineCollector(),
        PerformanceProfileCollector(),
        SandboxTestsCollector(),
        JSApiExtractorCollector(),
    ]


def collectors_by_id() -> Dict[str, BaseCollector]:
    return {c.META.collector_id: c for c in default_collectors()}
