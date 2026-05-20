"""
TL hook registration utilities. API-compatible with Android SDK.

Usage:
    from hook_utils import add_tl_hook

    add_tl_hook("messages.sendReaction", on_send_reaction)

    def on_send_reaction(tl_obj):
        tl_obj["big"] = True
"""

import _ios_bridge

# ---------------------------------------------------------------------------
# TL hooks
# ---------------------------------------------------------------------------

def add_tl_hook(tl_type: str, callback) -> None:
    """
    Register callback for a TL message type.

    callback(tl_obj: dict) is called synchronously before the TL request is
    dispatched. Modify tl_obj in-place to change parameters.

    tl_type examples:
        "messages.sendReaction"   — reaction send
        "messages.sendMessage"    — text message send
        "messages.forwardMessages" — forward
    """
    _ios_bridge.add_tl_hook(tl_type, callback)


# ---------------------------------------------------------------------------
# Android compatibility: find_class maps Android class names to ObjC/Python
# ---------------------------------------------------------------------------

def find_class(module: str, name: str):
    """
    Android: finds a Java class.
    iOS: returns a Python callable that no-ops, preserving source compatibility.
    """
    class _AndroidClassStub:
        _name = f"{module}.{name}"

        def __getattr__(self, item):
            return lambda *args, **kwargs: None

    return _AndroidClassStub()


# ---------------------------------------------------------------------------
# Android compatibility: method hooks via ObjC swizzling
# ---------------------------------------------------------------------------

def add_method_hook(class_name: str, method_name: str, before=None, after=None) -> None:
    """
    Android: hooks a Java method via reflection.
    iOS: hooks an ObjC method via EGObjCSwizzler (future implementation).
    """
    # TODO: implement ObjC swizzling via _ios_bridge.swizzle(class_name, method_name, before, after)
    pass
