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
        param.args[0] = "modified title"            # mutate args in place

    def after(param):
        if param.getResult() is None:
            param.setResult("default")              # override return value

    add_method_hook("UIViewController", "setTitle:", before=before, after=after)

Method hooks — Xposed/Android OOP style
---------------------------------------
    from hook_utils import MethodHook, hook_method

    class TitleHook(MethodHook):
        def before_hooked_method(self, param):
            param.args[0] = "[plugin] " + str(param.args[0])

        def after_hooked_method(self, param):
            # param.setResult() in before would have skipped this entirely.
            pass

    hook_method("UIViewController", "setTitle:", TitleHook())

    # Skip the original entirely (with optional substitute result):
    class Block(MethodHook):
        def before_hooked_method(self, param):
            param.setResult(False)   # original + all after_hooked_method skipped
    hook_method("UIApplication", "openURL:", Block())
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
        "messages.sendReaction"     — reaction send
        "messages.sendMessage"      — text message send
        "messages.forwardMessages"  — forward
    """
    _ios_bridge.add_tl_hook(tl_type, callback)


# ---------------------------------------------------------------------------
# Method hooks
# ---------------------------------------------------------------------------

class MethodHookParam:
    """
    Argument passed to before/after method-hook callbacks. Mirrors the
    Android/Xposed XC_MethodHook.MethodHookParam that exteraGram for Android
    exposes via Chaquopy.

    Attributes (snake_case — preferred iOS naming):
        this_object: receiver of the hooked call
        method:      ObjC selector string (e.g. "setTitle:")
        args:        list of arguments (idx 0/1 — self/_cmd — are excluded).
                     Mutate elements in `before` to change what the original
                     receives; element types map id↔Python-object, numeric↔
                     int/float/bool, SEL/Class↔str. Unsupported types appear
                     as None and writes are ignored.
        result:      return value of the original (only valid in `after`).

    Android compatibility:
        param.thisObject       — alias for `this_object`
        param.getResult()      — alias for `result` getter
        param.setResult(value) — alias for set_result(); in `before` it also
                                 skips the original method and all
                                 `after_hooked_method` callbacks (Xposed semantics).
    """

    # __slots__ pruned of `args`/`result`/`this_object` since they're plain attrs;
    # leaving them out keeps the class flexible for arbitrary attribute reads
    # that some Android-source plugins may rely on.

    def __init__(self):
        self.this_object = None
        self.method = ""
        self.args = []
        self.result = None
        self._override_result = False
        self._skip_original = False

    # --- snake_case API (preferred on iOS) ---

    def set_result(self, value) -> None:
        """Override the return value of the hooked method."""
        self.result = value
        self._override_result = True

    def get_result(self):
        """Current return value (None until the original is invoked or set_result is called)."""
        return self.result

    def skip_original(self) -> None:
        """
        Don't call the original IMP. Calls to set_result() also imply this
        when invoked from `before`. Call set_result() first if the caller
        expects a return value — otherwise the slot stays zero-initialised.
        """
        self._skip_original = True

    # --- Android/Xposed camelCase aliases ---

    @property
    def thisObject(self):
        return self.this_object

    @thisObject.setter
    def thisObject(self, value):
        self.this_object = value

    def setResult(self, value) -> None:
        """Xposed alias for set_result()."""
        self.set_result(value)

    def getResult(self):
        """Xposed alias for get_result()."""
        return self.get_result()


class MethodHook:
    """
    Android/Xposed-style OOP hook wrapper. Subclass and override the methods
    you care about, then register the instance with `hook_method()`.

        class MyHook(MethodHook):
            def before_hooked_method(self, param): ...
            def after_hooked_method(self, param): ...

        hook_method("UIViewController", "viewDidLoad", MyHook())

    On Android this would be passed to XposedBridge.hookMethod(method, hook);
    on iOS hook_method() forwards to add_method_hook() with the bound methods.
    """

    def before_hooked_method(self, param: "MethodHookParam") -> None:
        """Called before the original method. Override in subclass."""
        pass

    def after_hooked_method(self, param: "MethodHookParam") -> None:
        """Called after the original method. Override in subclass."""
        pass


def add_method_hook(class_name: str, method_name: str,
                    before=None, after=None) -> bool:
    """
    Hook an Objective-C instance method (functional API).

    class_name:    ObjC class name (e.g. "UIViewController", "MTPMessagesController")
    method_name:   selector string, including colons
                   (e.g. "viewDidLoad", "tableView:didSelectRowAtIndexPath:")
    before(param): called before the original. Receives MethodHookParam.
    after(param):  called after the original. May read/override param.result.

    Returns True if the class+selector was found and the hook is installed.

    Notes:
      * Hooks installed on a class do NOT automatically fire for subclass
        overrides — hook the subclass directly if it overrides the method.
      * Struct args (CGRect, CGPoint, ...) and raw pointers appear as None and
        cannot be mutated through `args`, but the original IMP still receives
        the correct values.
      * setResult/skip_original called in `before` will skip the original and
        all `after` callbacks (Xposed-compatible behaviour).
    """
    try:
        return bool(_ios_bridge.add_method_hook(class_name, method_name, before, after))
    except AttributeError:
        return False


def hook_method(class_name: str, method_name: str, hook: MethodHook) -> bool:
    """
    Android/Xposed-style hook registration. Equivalent to:

        add_method_hook(class_name, method_name,
                        before=hook.before_hooked_method,
                        after=hook.after_hooked_method)
    """
    if hook is None:
        return False
    return add_method_hook(
        class_name, method_name,
        before=hook.before_hooked_method,
        after=hook.after_hooked_method,
    )


# ---------------------------------------------------------------------------
# Android compatibility: find_class
# ---------------------------------------------------------------------------

def find_class(*args):
    """
    Android: find_class("android.widget.Toast") returns a Java Class.
    iOS: returns an opaque stub keeping source compatibility — most Android
         code that uses find_class is doing reflection that has no ObjC
         equivalent. Use add_method_hook / hook_method to hook ObjC classes
         by name directly instead.

    Accepts either find_class("full.qualified.Name") or the legacy
    find_class(module, name) two-argument form.
    """
    if len(args) == 1:
        full_name = args[0]
    elif len(args) == 2:
        full_name = ".".join(args)
    else:
        return None

    class _AndroidClassStub:
        _name = full_name

        def __getattr__(self, item):
            return lambda *a, **kw: None

    return _AndroidClassStub()
