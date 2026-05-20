"""
File system utilities for plugins. API-compatible with Android SDK.

Plugins should only read/write within their data directory.
Paths outside the plugin's data dir are blocked.
"""

import os
import _ios_bridge


def get_plugin_data_dir(plugin_id: str) -> str:
    """Return the writable data directory for the given plugin."""
    try:
        path = _ios_bridge.get_plugin_data_dir(plugin_id)
    except AttributeError:
        # Fallback: use Documents/EGPlugins/.data/<id>
        docs = os.path.expanduser("~/Documents")
        path = os.path.join(docs, "EGPlugins", ".data", plugin_id)
    os.makedirs(path, exist_ok=True)
    return path


def read_file(path: str, encoding: str = "utf-8") -> str:
    """Read a text file and return its contents."""
    with open(path, "r", encoding=encoding) as f:
        return f.read()


def write_file(path: str, content: str, encoding: str = "utf-8") -> None:
    """Write content to a text file, creating parent directories as needed."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding=encoding) as f:
        f.write(content)


def read_json(path: str) -> dict:
    """Read and parse a JSON file."""
    import json
    with open(path, "r") as f:
        return json.load(f)


def write_json(path: str, data, indent: int = 2) -> None:
    """Write data as JSON to a file."""
    import json
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=indent, ensure_ascii=False)
