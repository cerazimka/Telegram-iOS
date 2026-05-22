"""
Base class for exteraGram iOS plugins.

Designed to be source-compatible with the exteraGram Android SDK so that
plugins written for Android can subclass `BasePlugin` and define
`on_plugin_load` / `on_plugin_unload` without changes.

Lifecycle (any one of these forms works; first found wins):
    class MyPlugin(BasePlugin):
        def on_plugin_load(self): ...   # Android-compatible
        def on_plugin_unload(self): ...

    class MyPlugin(Plugin):
        def on_load(self): ...          # iOS-native short form
        def on_unload(self): ...

    # Or module-level functions (legacy iOS form):
    def on_load(plugin): ...
    def on_unload(plugin): ...
"""


class Plugin:
    """Base class — Python-side. Subclass and override the lifecycle methods."""

    def __init__(self):
        # Try in order: class attribute, module-level __id__, class name.
        pid = getattr(type(self), "__id__", None)
        if pid is None:
            try:
                import sys
                mod = sys.modules.get(type(self).__module__)
                pid = getattr(mod, "__id__", None) if mod else None
            except Exception:
                pid = None
        self.__settings_prefix__ = pid or type(self).__name__
        # Hook handles returned by hook_method() — kept so unhook_method() works
        # and so the engine can tear hooks down at unload time.
        self.hook_refs = []
        # Menu item handles registered via add_menu_item() — currently stubs.
        self._menu_items = []

    # ------------------------------------------------------------------
    # Lifecycle — override in subclass. Both pairs are supported; the loader
    # tries `on_plugin_load`/`on_plugin_unload` first (Android convention),
    # then falls back to `on_load`/`on_unload`.
    # ------------------------------------------------------------------

    def on_plugin_load(self) -> None:
        """Android-compatible entry point. Default: delegate to on_load()."""
        self.on_load()

    def on_plugin_unload(self) -> None:
        """Android-compatible exit point. Default: delegate to on_unload()."""
        self.on_unload()

    def on_load(self) -> None:
        """iOS-native entry point. Override in subclass."""
        pass

    def on_unload(self) -> None:
        """iOS-native exit point. Override in subclass."""
        pass

    # ------------------------------------------------------------------
    # Logging / settings
    # ------------------------------------------------------------------

    def log(self, *args) -> None:
        from android_utils import log as _log
        _log(" ".join(str(a) for a in args))

    def get_setting(self, key: str, default=None):
        from android_utils import get_plugin_setting
        return get_plugin_setting(self.__settings_prefix__, key, default)

    def set_setting(self, key: str, value, reload_settings: bool = False) -> None:
        from android_utils import set_plugin_setting
        set_plugin_setting(self.__settings_prefix__, key, value)
        # `reload_settings` is an Android-side concept (rebuild the settings UI);
        # the iOS bridge handles this implicitly when the screen is reopened.

    # ------------------------------------------------------------------
    # Hooks
    # ------------------------------------------------------------------
    #
    # Android style:
    #     method = SomeClass.getClass().getDeclaredMethod("foo", ArgType)
    #     self.hook_method(method, MyHook())          # 2 args, Method + Hook
    #
    # iOS-native style:
    #     self.hook_method("SomeClass", "foo:", MyHook())  # 3 args, str/str/Hook
    #
    # Both forms are accepted. The 2-arg form expects the first argument to be
    # a MethodProxy returned by hook_utils.find_class(...).getClass().getDeclaredMethod(...).

    def hook_method(self, *args):
        """
        Install a method hook. Returns a handle suitable for unhook_method().

        Forms:
            hook_method(class_name: str, selector: str, hook: MethodHook)
            hook_method(method_proxy, hook: MethodHook)   # Android-compat
        """
        from hook_utils import hook_method as _impl, MethodProxy
        if len(args) == 3:
            class_name, selector, hook = args
            ok = _impl(class_name, selector, hook)
        elif len(args) == 2:
            first, hook = args
            if isinstance(first, MethodProxy):
                ok = _impl(first.class_name, first.selector, hook)
            elif isinstance(first, str):
                # Caller passed only a class name and a hook — selector unknown.
                self.log(f"hook_method: missing selector for class '{first}'")
                ok = False
            else:
                self.log(f"hook_method: unsupported first argument {type(first).__name__}")
                ok = False
        else:
            self.log(f"hook_method: expected 2 or 3 arguments, got {len(args)}")
            return None

        if ok:
            ref = (args[0], args[1] if len(args) == 3 else None)
            self.hook_refs.append(ref)
            return ref
        return None

    def unhook_method(self, ref) -> None:
        """
        Remove a previously installed hook. Currently a no-op on iOS — the
        underlying ObjC trampoline is permanent for the process lifetime — but
        the handle is dropped from the per-plugin list so on_plugin_unload
        bookkeeping stays accurate.
        """
        try:
            self.hook_refs.remove(ref)
        except ValueError:
            pass

    # ------------------------------------------------------------------
    # Menu items — stubs for Android source compatibility.
    # Real menu integration requires Swift-side work; these accept the call
    # and remember the handle so plugins don't crash.
    # ------------------------------------------------------------------

    def add_menu_item(self, item) -> object:
        self._menu_items.append(item)
        return item

    def remove_menu_item(self, ref) -> None:
        try:
            self._menu_items.remove(ref)
        except ValueError:
            pass


# Android-source-compatible alias. Plugins can write:
#     from base_plugin import BasePlugin
#     class MyPlugin(BasePlugin): ...
BasePlugin = Plugin


# Re-export MethodHook from hook_utils so Android plugins doing
# `from base_plugin import MethodHook` keep working.
def __getattr__(name):
    if name == "MethodHook":
        from hook_utils import MethodHook
        return MethodHook
    raise AttributeError(name)
