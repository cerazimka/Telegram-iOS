"""
Internal SDK helpers used by the iOS bridge. Plugin code MUST NOT import this
module — its API is engine-private and may change without notice.

The bridge calls these helpers to:
  * discover whether a plugin has settings,
  * snapshot the SettingItem list for rendering,
  * dispatch on_change / on_click callbacks back into Python.

Callbacks are looked up by item index in the most recently rendered snapshot,
so the Swift UI must rebuild against the latest `get_settings_items` result
before invoking change/click.
"""

import sys

# plugin_id -> [SettingItem, ...]  (raw Python instances, kept so callbacks
# survive the trip through the bridge serialisation).
_settings_cache: dict = {}


# ---------------------------------------------------------------------------
# Public helpers (called from EGIOSBridge.m)
# ---------------------------------------------------------------------------

def has_settings(plugin_id: str) -> bool:
    """True if the plugin declares any settings (via create_settings or __settings__)."""
    module = sys.modules.get(plugin_id)
    if module is None:
        return False
    instance = getattr(module, "__eg_instance__", None)
    if instance is not None and callable(getattr(instance, "create_settings", None)):
        return True
    return getattr(module, "__settings__", None) is not None


def get_settings_items(plugin_id: str) -> list:
    """
    Return [item.to_dict(), ...] for the plugin's current settings. Caches the
    underlying SettingItem instances by index so subsequent invoke_change /
    invoke_click calls can locate callbacks.

    Returns an empty list if the plugin has no settings or cannot be found.
    """
    module = sys.modules.get(plugin_id)
    if module is None:
        return []
    items = _collect_items(module)
    _settings_cache[plugin_id] = items
    return [_serialise(item, idx) for idx, item in enumerate(items)]


def invoke_change(plugin_id: str, index: int, value) -> bool:
    """Fire on_change for the item at `index`. Returns True on success."""
    cb = _lookup(plugin_id, index, "on_change")
    if cb is None:
        return False
    try:
        cb(value)
        # If this is a toggle/selector/input/slider with a `key`, also persist
        # the new value via the standard plugin-setting bridge.
        items = _settings_cache.get(plugin_id) or []
        if 0 <= index < len(items):
            item = items[index]
            key = getattr(item, "key", "")
            if key:
                _persist(plugin_id, key, value)
    except Exception as exc:
        _log(plugin_id, f"on_change raised: {exc}")
    return True


def invoke_click(plugin_id: str, index: int) -> bool:
    """Fire on_click for the item at `index`. Returns True on success."""
    cb = _lookup(plugin_id, index, "on_click")
    if cb is None:
        return False
    try:
        cb(None)
    except Exception as exc:
        _log(plugin_id, f"on_click raised: {exc}")
    return True


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

def _collect_items(module) -> list:
    instance = getattr(module, "__eg_instance__", None)
    if instance is not None and callable(getattr(instance, "create_settings", None)):
        try:
            res = instance.create_settings()
            if res:
                return list(res)
        except Exception as exc:
            _log(getattr(module, "__id__", "?"), f"create_settings raised: {exc}")
            return []
    settings = getattr(module, "__settings__", None)
    if settings is None:
        return []
    if hasattr(settings, "items"):
        return list(settings.items)
    if isinstance(settings, list):
        return settings
    return []


def _serialise(item, idx: int) -> dict:
    if hasattr(item, "to_dict"):
        d = item.to_dict()
    elif isinstance(item, dict):
        d = dict(item)
    else:
        d = {"type": "text", "title": str(item)}
    d["index"] = idx
    # Expose whether callbacks exist so the renderer can decide if a row is tappable.
    d["has_on_change"] = getattr(item, "on_change", None) is not None
    d["has_on_click"]  = getattr(item, "on_click",  None) is not None
    return d


def _lookup(plugin_id: str, index: int, attr: str):
    items = _settings_cache.get(plugin_id) or []
    if 0 <= index < len(items):
        return getattr(items[index], attr, None)
    return None


def _persist(plugin_id: str, key: str, value) -> None:
    try:
        import _ios_bridge
        _ios_bridge.set_plugin_setting(plugin_id, key, value)
    except Exception:
        pass


def _log(plugin_id, message: str) -> None:
    try:
        import _ios_bridge
        _ios_bridge.log_text(f"[settings:{plugin_id}] {message}", "PluginEngine")
    except Exception:
        pass
