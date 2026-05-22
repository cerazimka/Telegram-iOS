"""
Hook registration utilities. Designed to be source-compatible with the
exteraGram Android plugin SDK so that plugins can run unmodified on iOS where
the underlying machinery (Java reflection vs ObjC runtime) allows.

TL hooks
--------
    from hook_utils import add_tl_hook

    def on_send_reaction(tl_obj):
        tl_obj["big"] = True

    add_tl_hook("messages.sendReaction", on_send_reaction)

Method hooks — functional style
-------------------------------
    from hook_utils import add_method_hook

    def before(param):
        param.args[0] = "modified title"

    def after(param):
        if param.getResult() is None:
            param.setResult("default")

    add_method_hook("UIViewController", "setTitle:", before=before, after=after)

Method hooks — Xposed/Android OOP style
---------------------------------------
    from hook_utils import MethodHook, hook_method

    class TitleHook(MethodHook):
        def before_hooked_method(self, param):
            param.args[0] = "[plugin] " + str(param.args[0])

    hook_method("UIViewController", "setTitle:", TitleHook())

Private field access (KVC)
--------------------------
    from hook_utils import get_private_field, set_private_field

    activity = param.thisObject
    name = get_private_field(activity, "title")      # [activity valueForKey:@"title"]
    set_private_field(activity, "title", "new")      # [activity setValue:@"new" forKey:@"title"]
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
    """
    _ios_bridge.add_tl_hook(tl_type, callback)


# ---------------------------------------------------------------------------
# ObjC object proxy
# ---------------------------------------------------------------------------

class ObjCObject:
    """
    Opaque wrapper around an Objective-C `id` pointer. Returned by the bridge
    whenever a non-primitive ObjC value flows into Python (hook arguments,
    return values, KVC reads).

    Supports KVC-style attribute access:
        obj.title             ↔ [obj valueForKey:@"title"]
        obj.title = "new"     ↔ [obj setValue:@"new" forKey:@"title"]

    The chained access shape `obj.getClass().getDeclaredMethod(...)` from
    Android plugins is also supported via stubs — see `find_class`.
    """

    __slots__ = ("_capsule", "_class_name")

    def __init__(self, capsule, class_name: str = ""):
        # `capsule` is a PyCapsule produced by _ios_bridge that holds a +1
        # retained `id`. Its destructor releases the retain when the wrapper
        # is garbage-collected.
        self._capsule = capsule
        self._class_name = class_name or _ios_bridge.objc_class_name(capsule)

    def __repr__(self) -> str:
        return f"<ObjC {self._class_name}>"

    # --- KVC attribute access ---

    def __getattr__(self, name: str):
        # __getattr__ only fires when normal lookup fails. Guard against
        # recursive lookups (e.g. before __init__ assigned _capsule) and
        # against dunder names which should never reach KVC.
        if name.startswith("_") or (name.startswith("__") and name.endswith("__")):
            raise AttributeError(name)
        try:
            return _ios_bridge.kvc_get(self._capsule, name)
        except Exception:
            # Common Android idioms — return a callable stub rather than raise.
            if name in ("getClass", "getName", "getId"):
                return lambda *a, **kw: self._class_name
            raise AttributeError(name)

    def __setattr__(self, name: str, value):
        if name in ObjCObject.__slots__:
            object.__setattr__(self, name, value)
            return
        try:
            _ios_bridge.kvc_set(self._capsule, name, value)
        except Exception:
            object.__setattr__(self, name, value)

    # --- Android-source-compat helpers ---

    def getClass(self):
        return _AndroidClassStub(self._class_name)


def get_private_field(obj, key: str):
    """
    KVC read. Equivalent to Android's reflection-based private field access.

    Works on ObjCObject (real KVC), plain dicts (item lookup), and any other
    Python object (attribute lookup). Returns None on failure.
    """
    if isinstance(obj, ObjCObject):
        try:
            return _ios_bridge.kvc_get(obj._capsule, key)
        except Exception:
            return None
    if isinstance(obj, dict):
        return obj.get(key)
    try:
        return getattr(obj, key)
    except AttributeError:
        return None


def set_private_field(obj, key: str, value) -> None:
    """KVC write. Counterpart to get_private_field."""
    if isinstance(obj, ObjCObject):
        try:
            _ios_bridge.kvc_set(obj._capsule, key, value)
        except Exception:
            pass
        return
    if isinstance(obj, dict):
        obj[key] = value
        return
    try:
        setattr(obj, key, value)
    except (AttributeError, TypeError):
        pass


# ---------------------------------------------------------------------------
# Method hooks
# ---------------------------------------------------------------------------

class MethodHookParam:
    """
    Argument passed to before/after method-hook callbacks. Mirrors the
    Android/Xposed XC_MethodHook.MethodHookParam exposed by exteraGram for
    Android via Chaquopy.

    Attributes (snake_case — preferred iOS naming):
        this_object: receiver of the hooked call (ObjCObject)
        method:      ObjC selector string (e.g. "setTitle:")
        args:        list of arguments (idx 0/1 — self/_cmd — are excluded).
                     Mutate elements in `before` to change what the original
                     receives. Object args appear as ObjCObject; primitive
                     types map naturally; unsupported types appear as None.
        result:      return value of the original (only valid in `after`).
                     Set via set_result() to override.

    Android compatibility:
        param.thisObject       — alias for `this_object`
        param.getResult()      — alias for `result` getter
        param.setResult(value) — alias for set_result(); in `before` it also
                                 skips the original method and all
                                 `after_hooked_method` callbacks.
    """

    def __init__(self):
        self.this_object = None
        self.method = ""
        self.args = []
        self.result = None
        self._override_result = False
        self._skip_original = False

    def set_result(self, value) -> None:
        self.result = value
        self._override_result = True

    def get_result(self):
        return self.result

    def skip_original(self) -> None:
        self._skip_original = True

    # Android/Xposed camelCase aliases

    @property
    def thisObject(self):
        return self.this_object

    @thisObject.setter
    def thisObject(self, value):
        self.this_object = value

    def setResult(self, value) -> None:
        self.set_result(value)

    def getResult(self):
        return self.get_result()


class MethodHook:
    """
    Android/Xposed-style OOP hook wrapper. Subclass and override the methods
    you care about, then register the instance with hook_method() or
    self.hook_method() on a BasePlugin subclass.
    """

    def before_hooked_method(self, param: "MethodHookParam") -> None:
        pass

    def after_hooked_method(self, param: "MethodHookParam") -> None:
        pass


def add_method_hook(class_name: str, method_name: str,
                    before=None, after=None) -> bool:
    """Hook an Objective-C instance method (functional API)."""
    try:
        return bool(_ios_bridge.add_method_hook(class_name, method_name, before, after))
    except AttributeError:
        return False


def hook_method(class_name: str, method_name: str, hook: MethodHook) -> bool:
    """Android/Xposed-style hook registration with a MethodHook subclass."""
    if hook is None:
        return False
    return add_method_hook(
        class_name, method_name,
        before=hook.before_hooked_method,
        after=hook.after_hooked_method,
    )


# ---------------------------------------------------------------------------
# Android reflection compatibility — find_class chain
# ---------------------------------------------------------------------------
#
# Android plugins typically write:
#
#     cls = find_class("com.example.Foo")
#     method = cls.getClass().getDeclaredMethod("bar", ArgType1, ArgType2)
#     method.setAccessible(True)
#     self.hook_method(method, MyHook())
#
# On iOS the FQ Java class name has no real equivalent, but the trailing
# component (`Foo`) sometimes matches a real ObjC class. The chain below
# returns stubs that remember the class+method names so hook_method() can
# extract them and call add_method_hook(class_name, selector, ...) directly.


class MethodProxy:
    """
    Stand-in for a java.lang.reflect.Method. Holds the class name and selector
    so BasePlugin.hook_method() can dispatch to add_method_hook().
    """

    __slots__ = ("class_name", "selector")

    def __init__(self, class_name: str, selector: str):
        self.class_name = class_name
        self.selector = selector

    def __repr__(self) -> str:
        return f"<MethodProxy -[{self.class_name} {self.selector}]>"

    def setAccessible(self, flag: bool) -> None:
        # Java reflection no-op equivalent — iOS hooks don't need access checks.
        pass

    def getName(self) -> str:
        return self.selector

    def getDeclaringClass(self):
        return _AndroidClassStub(self.class_name)

    # Some plugins call invoke() — return None silently rather than crash.
    def invoke(self, *args, **kwargs):
        return None


class _AndroidClassStub:
    """
    Result of find_class("a.b.C") or ObjCObject.getClass(). Exposes a small
    surface of Java-reflection methods so chained calls in plugin code don't
    immediately blow up. Real ObjC introspection is intentionally limited —
    this is for source compatibility, not full reflection.
    """

    __slots__ = ("_name",)

    def __init__(self, name: str):
        self._name = name

    def __repr__(self) -> str:
        return f"<AndroidClassStub {self._name}>"

    @property
    def TYPE(self):
        return self

    def getName(self) -> str:
        return self._name

    def getSimpleName(self) -> str:
        return self._name.rsplit(".", 1)[-1]

    def getClass(self):
        return self

    def getDeclaredMethod(self, name: str, *param_types) -> MethodProxy:
        return MethodProxy(self._simple_name(), self._to_selector(name, param_types))

    def getDeclaredMethods(self):
        return []

    def getDeclaredConstructor(self, *param_types) -> MethodProxy:
        return MethodProxy(self._simple_name(), "init")

    def getDeclaredField(self, name: str):
        return _FieldProxy(self._simple_name(), name)

    # Convert a Java method name + arg-type tuple to a best-effort ObjC
    # selector. Without real signature info this is a guess (the colon count
    # equals the number of declared parameters); plugins that need exact
    # matching should pass `class_name, "selector:"` to hook_method directly.
    def _to_selector(self, java_name: str, param_types) -> str:
        if not param_types:
            return java_name
        return java_name + ":" * len(param_types)

    def _simple_name(self) -> str:
        return self._name.rsplit(".", 1)[-1]


class _FieldProxy:
    """Stub for java.lang.reflect.Field. Used by KVC fallback paths."""

    __slots__ = ("class_name", "field_name")

    def __init__(self, class_name: str, field_name: str):
        self.class_name = class_name
        self.field_name = field_name

    def setAccessible(self, flag: bool) -> None:
        pass

    def get(self, obj):
        return get_private_field(obj, self.field_name)

    def set(self, obj, value) -> None:
        set_private_field(obj, self.field_name, value)


def find_class(*args):
    """
    Android: find_class("android.widget.Toast") returns a Java Class.
    iOS: returns a stub remembering the FQ name. The trailing component is
         treated as the ObjC class name candidate for hooks; the rest of the
         chain (getClass / getDeclaredMethod / setAccessible) is implemented
         as best-effort proxies.

    Accepts either find_class("full.Name") or the legacy find_class(module, name).
    """
    if len(args) == 1:
        full_name = args[0]
    elif len(args) == 2:
        full_name = ".".join(args)
    else:
        return None
    return _AndroidClassStub(full_name)
