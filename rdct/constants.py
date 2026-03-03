from __future__ import annotations

"""RDCT constants.

Kept in a separate module so both Core and WebUI/API can share versioned identifiers.
"""

TOOL_NAME = "RDCT"

# NOTE: bump together with pyproject.toml
TOOL_VERSION = "0.3.0"

# Versioned public API
API_VERSION = "1.0"

# Versioned UI bundle (static files)
UI_VERSION = "0.3"

SUPPORTED_ARCH = ["mipsel", "mips", "aarch64"]
SUPPORTED_LANGUAGES = ["ru", "en"]

# Snapshot / JSON formats
MANIFEST_VERSION = "1.2.0"
RESULT_VERSION = "1.1.0"
ERRORS_VERSION = "1.1.0"
DIFF_VERSION = "1.0.0"
MIRROR_INDEX_VERSION = "1.0.0"
