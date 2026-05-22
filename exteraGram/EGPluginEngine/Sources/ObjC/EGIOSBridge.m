// MARK: exteraGram — EGPluginEngine ObjC/Python bridge implementation

#import "EGIOSBridge.h"
#import "EGObjCSwizzler.h"
#import <UIKit/UIKit.h>
#import <os/log.h>
#import <ZipArchive/ZipArchive.h>
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// CPython C API — only compiled when the framework is present.
// To activate: add Python.xcframework to third-party/Python/ and update BUILD.
// ---------------------------------------------------------------------------
#if __has_include(<Python/Python.h>)
#define EGPLUGIN_HAS_PYTHON 1
#import <Python/Python.h>
#endif

// ---------------------------------------------------------------------------
// Logging helper (ObjC side, calls back into Swift EGLoggerBridge)
// ---------------------------------------------------------------------------

// Declared in Swift as:
//   @objc public static func logFromPlugin(tag: String, message: String)
// We forward-declare it so ObjC can call it without importing the Swift module.
@class EGLoggerBridgeImpl;
extern void EGLoggerBridgeImpl_logFromPlugin(NSString *tag, NSString *message);

// Swift @_cdecl bridge — synchronous write to EGPluginDebugLog (no async dispatch).
// Declared in EGPluginDebugLog.swift.
extern void EGPluginDebugLog_appendCStr(const char *tag, const char *message);

// Swift @_cdecl bridges — localisation. Declared in EGStringsBridge.swift.
// Both return strdup'd strings — caller must free().
extern const char *EGStringsBridge_currentLanguageCStr(void);
extern const char *EGStringsBridge_localizedStringCStr(const char *key);

// Swift @_cdecl bridges — client info & data dir. Declared in EGPluginClientInfo.swift.
extern int64_t EGPluginClientInfo_getAccountId(void);
extern int64_t EGPluginClientInfo_getUserId(void);
extern const char *EGPluginClientInfo_getConnectionStateCStr(void);
extern const char *EGPluginClientInfo_getPluginDataDirCStr(const char *plugin_id);

static void plugin_log(NSString *tag, NSString *fmt, ...) NS_FORMAT_FUNCTION(2, 3);
static void plugin_log(NSString *tag, NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    os_log(OS_LOG_DEFAULT, "[SG.%{public}@] %{public}@", tag, msg);
    [EGPythonBridge logFromPlugin:tag message:msg];
}

// ---------------------------------------------------------------------------
// Global Python state (only used when EGPLUGIN_HAS_PYTHON)
// ---------------------------------------------------------------------------

#if EGPLUGIN_HAS_PYTHON

// Dict: {"tl_type": [callback, ...]}
static PyObject *g_tl_hooks = NULL;
// Dict: {"plugin_id": module}
static PyObject *g_loaded_modules = NULL;
// Dict: {"ClassName.selector:": [{"before": cb, "after": cb}, ...]} for ObjC method hooks
static PyObject *g_method_hooks = NULL;
static BOOL g_initialized = NO;

// ---------------------------------------------------------------------------
// Python C extension: _ios_bridge
// ---------------------------------------------------------------------------

static PyObject *py_log_text(PyObject *self, PyObject *args) {
    const char *tag = "Plugin";
    const char *msg = "";
    if (!PyArg_ParseTuple(args, "s|s", &msg, &tag)) {
        PyErr_Clear();
        if (!PyArg_ParseTuple(args, "s", &msg)) return NULL;
    }
    NSString *nsTag = [NSString stringWithUTF8String:tag];
    NSString *nsMsg = [NSString stringWithUTF8String:msg];
    // Dispatch async so we don't block the plugin while logging
    dispatch_async(dispatch_get_main_queue(), ^{
        [EGPythonBridge logFromPlugin:nsTag message:nsMsg];
    });
    Py_RETURN_NONE;
}

static PyObject *py_add_tl_hook(PyObject *self, PyObject *args) {
    const char *tl_type;
    PyObject *callback;
    if (!PyArg_ParseTuple(args, "sO", &tl_type, &callback)) return NULL;
    if (!PyCallable_Check(callback)) {
        PyErr_SetString(PyExc_TypeError, "callback must be callable");
        return NULL;
    }
    if (!g_tl_hooks) {
        PyErr_SetString(PyExc_RuntimeError, "_ios_bridge not initialized");
        return NULL;
    }
    PyObject *list = PyDict_GetItemString(g_tl_hooks, tl_type);
    if (!list) {
        list = PyList_New(0);
        PyDict_SetItemString(g_tl_hooks, tl_type, list);
        Py_DECREF(list);
        list = PyDict_GetItemString(g_tl_hooks, tl_type);
    }
    PyList_Append(list, callback);
    Py_RETURN_NONE;
}

static PyObject *py_has_hook(PyObject *self, PyObject *args) {
    const char *tl_type;
    if (!PyArg_ParseTuple(args, "s", &tl_type)) return NULL;
    if (!g_tl_hooks) Py_RETURN_FALSE;
    PyObject *list = PyDict_GetItemString(g_tl_hooks, tl_type);
    if (list && PyList_Size(list) > 0) Py_RETURN_TRUE;
    Py_RETURN_FALSE;
}

static PyObject *py_run_on_main_thread(PyObject *self, PyObject *args) {
    PyObject *callable;
    if (!PyArg_ParseTuple(args, "O", &callable)) return NULL;
    if (!PyCallable_Check(callable)) {
        PyErr_SetString(PyExc_TypeError, "argument must be callable");
        return NULL;
    }
    Py_INCREF(callable);
    dispatch_async(dispatch_get_main_queue(), ^{
        PyGILState_STATE state = PyGILState_Ensure();
        PyObject *result = PyObject_CallFunctionObjArgs(callable, NULL);
        if (!result) PyErr_Clear();
        else Py_DECREF(result);
        Py_DECREF(callable);
        PyGILState_Release(state);
    });
    Py_RETURN_NONE;
}

// show_alert(title, message, button="OK")
static PyObject *py_show_alert(PyObject *self, PyObject *args) {
    const char *title   = "";
    const char *message = "";
    const char *button  = "OK";
    if (!PyArg_ParseTuple(args, "ss|s", &title, &message, &button)) return NULL;
    NSString *nsTitle   = [NSString stringWithUTF8String:title];
    NSString *nsMessage = [NSString stringWithUTF8String:message];
    NSString *nsButton  = [NSString stringWithUTF8String:button];
    // Delay 1.0s so any presenting sheet / install flow can finish dismissing first.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // Find the topmost presented VC using connected scenes (iOS 13+).
        UIWindow *keyWin = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in scene.windows) {
                    if (w.isKeyWindow) { keyWin = w; break; }
                }
            }
            if (keyWin) break;
        }
        if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;
        UIViewController *root = keyWin.rootViewController;
        // Skip VCs that are in the middle of being dismissed — presenting from them fails silently.
        while (root.presentedViewController && !root.presentedViewController.isBeingDismissed) {
            root = root.presentedViewController;
        }
        // If root itself is being dismissed, step back to its presenter.
        while (root && root.isBeingDismissed && root.presentingViewController) {
            root = root.presentingViewController;
        }
        if (!root) return;
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:nsTitle
                             message:nsMessage
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:nsButton
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [root presentViewController:alert animated:YES completion:nil];
    });
    Py_RETURN_NONE;
}

// show_toast(message, duration=2.0)
static PyObject *py_show_toast(PyObject *self, PyObject *args) {
    const char *message = "";
    double duration = 2.0;
    if (!PyArg_ParseTuple(args, "s|d", &message, &duration)) return NULL;
    NSString *nsMsg = [NSString stringWithUTF8String:message];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"EGPluginShowToastNotification"
                          object:nil
                        userInfo:@{@"message": nsMsg, @"duration": @(duration)}];
    });
    Py_RETURN_NONE;
}

// copy_to_clipboard(text)
static PyObject *py_copy_to_clipboard(PyObject *self, PyObject *args) {
    const char *text = "";
    if (!PyArg_ParseTuple(args, "s", &text)) return NULL;
    NSString *nsText = [NSString stringWithUTF8String:text];
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIPasteboard generalPasteboard].string = nsText;
    });
    Py_RETURN_NONE;
}

// open_url(url)
static PyObject *py_open_url(PyObject *self, PyObject *args) {
    const char *url = "";
    if (!PyArg_ParseTuple(args, "s", &url)) return NULL;
    NSString *nsUrl = [NSString stringWithUTF8String:url];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *u = [NSURL URLWithString:nsUrl];
        if (u && [[UIApplication sharedApplication] canOpenURL:u]) {
            [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
        }
    });
    Py_RETURN_NONE;
}

// haptic_feedback(style="medium")
//   "light"|"medium"|"heavy" → UIImpactFeedbackGenerator
//   "success"|"warning"|"error" → UINotificationFeedbackGenerator
static PyObject *py_haptic_feedback(PyObject *self, PyObject *args) {
    const char *style = "medium";
    if (!PyArg_ParseTuple(args, "|s", &style)) return NULL;
    NSString *nsStyle = [NSString stringWithUTF8String:style];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([nsStyle isEqualToString:@"success"] ||
            [nsStyle isEqualToString:@"warning"] ||
            [nsStyle isEqualToString:@"error"]) {
            UINotificationFeedbackGenerator *gen = [UINotificationFeedbackGenerator new];
            UINotificationFeedbackType type = UINotificationFeedbackTypeSuccess;
            if      ([nsStyle isEqualToString:@"warning"]) type = UINotificationFeedbackTypeWarning;
            else if ([nsStyle isEqualToString:@"error"])   type = UINotificationFeedbackTypeError;
            [gen notificationOccurred:type];
        } else {
            UIImpactFeedbackStyle s = UIImpactFeedbackStyleMedium;
            if      ([nsStyle isEqualToString:@"light"]) s = UIImpactFeedbackStyleLight;
            else if ([nsStyle isEqualToString:@"heavy"]) s = UIImpactFeedbackStyleHeavy;
            UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:s];
            [gen impactOccurred];
        }
    });
    Py_RETURN_NONE;
}

// get_locale_language() -> str
static PyObject *py_get_locale_language(PyObject *self, PyObject *args) {
    const char *lang = EGStringsBridge_currentLanguageCStr();
    PyObject *result = PyUnicode_FromString(lang ?: "en");
    if (lang) free((void *)lang);
    return result;
}

// get_string(key, default="") -> str
static PyObject *py_get_string(PyObject *self, PyObject *args) {
    const char *key = "";
    const char *def = "";
    if (!PyArg_ParseTuple(args, "s|s", &key, &def)) return NULL;
    const char *value = EGStringsBridge_localizedStringCStr(key);
    PyObject *result;
    // EGLocalizationManager returns the key itself if not found — fall back to default.
    if (value && strcmp(value, key) != 0 && strlen(value) > 0) {
        result = PyUnicode_FromString(value);
    } else {
        result = PyUnicode_FromString(def);
    }
    if (value) free((void *)value);
    return result;
}

// ---------------------------------------------------------------------------
// Plugin settings (UserDefaults, namespaced eg.plugin.<id>.<key>)
// ---------------------------------------------------------------------------

static NSString *settingKey(const char *plugin_id, const char *key) {
    return [NSString stringWithFormat:@"eg.plugin.%s.%s", plugin_id ?: "", key ?: ""];
}

// get_plugin_setting(plugin_id, key, default=None) -> Any
static PyObject *py_get_plugin_setting(PyObject *self, PyObject *args) {
    const char *plugin_id = "", *key = "";
    PyObject *def = Py_None;
    if (!PyArg_ParseTuple(args, "ss|O", &plugin_id, &key, &def)) return NULL;
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:settingKey(plugin_id, key)];
    if (value == nil) {
        Py_INCREF(def);
        return def;
    }
    PyObject *py = ns_to_py(value);
    if (py) return py;
    Py_INCREF(def);
    return def;
}

// set_plugin_setting(plugin_id, key, value)
static PyObject *py_set_plugin_setting(PyObject *self, PyObject *args) {
    const char *plugin_id = "", *key = "";
    PyObject *value;
    if (!PyArg_ParseTuple(args, "ssO", &plugin_id, &key, &value)) return NULL;
    NSString *k = settingKey(plugin_id, key);
    if (value == Py_None) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:k];
    } else {
        id ns = py_to_ns(value);
        if (ns && ns != [NSNull null]) {
            [[NSUserDefaults standardUserDefaults] setObject:ns forKey:k];
        } else {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:k];
        }
    }
    Py_RETURN_NONE;
}

// ---------------------------------------------------------------------------
// Plugin data directory
// ---------------------------------------------------------------------------

// get_plugin_data_dir(plugin_id) -> str
static PyObject *py_get_plugin_data_dir(PyObject *self, PyObject *args) {
    const char *plugin_id = "";
    if (!PyArg_ParseTuple(args, "s", &plugin_id)) return NULL;
    const char *path = EGPluginClientInfo_getPluginDataDirCStr(plugin_id);
    PyObject *result = PyUnicode_FromString(path ?: "");
    if (path) free((void *)path);
    return result;
}

// ---------------------------------------------------------------------------
// Telegram client info
// ---------------------------------------------------------------------------

// get_account_id() -> int
static PyObject *py_get_account_id(PyObject *self, PyObject *args) {
    return PyLong_FromLongLong(EGPluginClientInfo_getAccountId());
}

// get_user_id() -> int
static PyObject *py_get_user_id(PyObject *self, PyObject *args) {
    return PyLong_FromLongLong(EGPluginClientInfo_getUserId());
}

// get_connection_state() -> str ("connected" | "connecting" | "updating" | "waiting_for_network")
static PyObject *py_get_connection_state(PyObject *self, PyObject *args) {
    const char *state = EGPluginClientInfo_getConnectionStateCStr();
    PyObject *result = PyUnicode_FromString(state ?: "connected");
    if (state) free((void *)state);
    return result;
}

// ---------------------------------------------------------------------------
// Method hooks (ObjC method swizzling driven by Python callbacks)
// ---------------------------------------------------------------------------
//
// add_method_hook(class_name, selector, before, after) registers per-(class, sel)
// Python callbacks. The first call for a (cls, sel) installs a forwardInvocation:
// trampoline via EGObjCSwizzler. The trampoline (eg_pythonMethodInvoker, defined
// below) marshals NSInvocation args ↔ Python, fires before/after callbacks and
// calls the original IMP through the alias selector.
//
// Supported types for marshaling: id, Class, SEL, BOOL/bool/char, short, int,
// long, long long (signed/unsigned), float, double, C string. Structs (CGRect,
// CGPoint, etc.) and arbitrary pointers are passed through opaquely: hooks see
// them as None in `args` and cannot modify them, but the original IMP still
// receives the correct values because NSInvocation's argument buffer is left
// untouched in that case.

// Skip type-encoding qualifier prefixes (r, n, N, o, O, R, V).
static const char *eg_strip_qualifiers(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

// Convert an NSInvocation argument (or return) buffer of the given ObjC type
// encoding to a Python object. Returns Py_None for unsupported types.
static PyObject *eg_value_to_py(const char *type, void *buf) {
    type = eg_strip_qualifiers(type);
    if (!type || !*type) Py_RETURN_NONE;
    switch (*type) {
        case '@': {
            __unsafe_unretained id obj = *(__unsafe_unretained id *)buf;
            return ns_to_py(obj);
        }
        case '#': {
            Class c = *(Class *)buf;
            return c ? PyUnicode_FromString(class_getName(c)) : (Py_INCREF(Py_None), Py_None);
        }
        case ':': {
            SEL s = *(SEL *)buf;
            return s ? PyUnicode_FromString(sel_getName(s)) : (Py_INCREF(Py_None), Py_None);
        }
        case 'B': return PyBool_FromLong(*(_Bool *)buf);
        case 'c': return PyLong_FromLong(*(signed char *)buf);
        case 'C': return PyLong_FromUnsignedLong(*(unsigned char *)buf);
        case 's': return PyLong_FromLong(*(short *)buf);
        case 'S': return PyLong_FromUnsignedLong(*(unsigned short *)buf);
        case 'i': return PyLong_FromLong(*(int *)buf);
        case 'I': return PyLong_FromUnsignedLong(*(unsigned int *)buf);
        case 'l': return PyLong_FromLong(*(long *)buf);
        case 'L': return PyLong_FromUnsignedLong(*(unsigned long *)buf);
        case 'q': return PyLong_FromLongLong(*(long long *)buf);
        case 'Q': return PyLong_FromUnsignedLongLong(*(unsigned long long *)buf);
        case 'f': return PyFloat_FromDouble(*(float *)buf);
        case 'd': return PyFloat_FromDouble(*(double *)buf);
        case '*': {
            const char *s = *(const char **)buf;
            return s ? PyUnicode_FromString(s) : (Py_INCREF(Py_None), Py_None);
        }
        default: Py_RETURN_NONE;
    }
}

// Read NSInvocation argument at `idx` into a Python object.
static PyObject *eg_invocation_arg_to_py(NSInvocation *inv, NSUInteger idx) {
    const char *type = [inv.methodSignature getArgumentTypeAtIndex:idx];
    NSUInteger size = 0;
    NSGetSizeAndAlignment(type, &size, NULL);
    if (size == 0) Py_RETURN_NONE;
    void *buf = alloca(size);
    memset(buf, 0, size);
    [inv getArgument:buf atIndex:idx];
    return eg_value_to_py(type, buf);
}

// Read NSInvocation return value into a Python object.
static PyObject *eg_invocation_return_to_py(NSInvocation *inv) {
    const char *type = inv.methodSignature.methodReturnType;
    NSUInteger size = inv.methodSignature.methodReturnLength;
    if (size == 0) Py_RETURN_NONE;  // void
    void *buf = alloca(size);
    memset(buf, 0, size);
    [inv getReturnValue:buf];
    return eg_value_to_py(type, buf);
}

// Marshal a Python value back into an NSInvocation arg / return slot.
// Returns YES if the value was applied, NO if the type is unsupported (caller
// should leave the original buffer untouched).
static BOOL eg_apply_py_arg_to_invocation(NSInvocation *inv, NSUInteger idx, PyObject *py, BOOL isReturn) {
    const char *type = isReturn ? inv.methodSignature.methodReturnType
                                : [inv.methodSignature getArgumentTypeAtIndex:idx];
    type = eg_strip_qualifiers(type);
    if (!type || !*type) return NO;

    // Handle the object case separately so ARC manages retention correctly.
    if (*type == '@') {
        id obj = py_to_ns(py);
        if (obj == [NSNull null]) obj = nil;
        if (isReturn) [inv setReturnValue:&obj];
        else          [inv setArgument:&obj atIndex:idx];
        return YES;
    }

    #define EG_SET(c_type, py_extract) do { \
        c_type v = (c_type)(py_extract); \
        if (isReturn) [inv setReturnValue:&v]; else [inv setArgument:&v atIndex:idx]; \
    } while (0)

    switch (*type) {
        case '#': {
            // Class: accept str name or None.
            Class c = Nil;
            if (PyUnicode_Check(py)) {
                const char *name = PyUnicode_AsUTF8(py);
                if (name) c = objc_getClass(name);
            }
            if (isReturn) [inv setReturnValue:&c]; else [inv setArgument:&c atIndex:idx];
            return YES;
        }
        case ':': {
            SEL s = NULL;
            if (PyUnicode_Check(py)) {
                const char *name = PyUnicode_AsUTF8(py);
                if (name) s = sel_registerName(name);
            }
            if (isReturn) [inv setReturnValue:&s]; else [inv setArgument:&s atIndex:idx];
            return YES;
        }
        case 'B': EG_SET(_Bool,    PyObject_IsTrue(py)); return YES;
        case 'c': {
            // BOOL on iOS is encoded as 'c' historically. Accept bool or int.
            signed char v;
            if (PyBool_Check(py)) v = (py == Py_True) ? 1 : 0;
            else v = (signed char)PyLong_AsLong(py);
            if (isReturn) [inv setReturnValue:&v]; else [inv setArgument:&v atIndex:idx];
            return YES;
        }
        case 'C': EG_SET(unsigned char,      PyLong_AsUnsignedLong(py)); return YES;
        case 's': EG_SET(short,              PyLong_AsLong(py));         return YES;
        case 'S': EG_SET(unsigned short,     PyLong_AsUnsignedLong(py)); return YES;
        case 'i': EG_SET(int,                PyLong_AsLong(py));         return YES;
        case 'I': EG_SET(unsigned int,       PyLong_AsUnsignedLong(py)); return YES;
        case 'l': EG_SET(long,               PyLong_AsLong(py));         return YES;
        case 'L': EG_SET(unsigned long,      PyLong_AsUnsignedLong(py)); return YES;
        case 'q': EG_SET(long long,          PyLong_AsLongLong(py));     return YES;
        case 'Q': EG_SET(unsigned long long, PyLong_AsUnsignedLongLong(py)); return YES;
        case 'f': EG_SET(float,              PyFloat_AsDouble(py));      return YES;
        case 'd': EG_SET(double,             PyFloat_AsDouble(py));      return YES;
        default:
            // Structs, pointers — unsupported. Caller leaves original buffer alone.
            return NO;
    }
    #undef EG_SET
}

// Lazy-load hook_utils.MethodHookParam (cached).
static PyObject *eg_method_hook_param_class(void) {
    static PyObject *cached = NULL;
    if (cached) return cached;
    PyObject *mod = PyImport_ImportModule("hook_utils");
    if (!mod) { PyErr_Clear(); return NULL; }
    PyObject *cls = PyObject_GetAttrString(mod, "MethodHookParam");
    Py_DECREF(mod);
    if (!cls) { PyErr_Clear(); return NULL; }
    cached = cls;  // keep strong ref
    return cached;
}

// The invoker block registered with EGObjCSwizzler for every hooked (class, sel).
// Runs on whatever thread the original call came in on. Acquires the GIL, fires
// `before` callbacks, invokes the original (unless skipped), fires `after`
// callbacks, and writes back any overridden return value.
static void eg_dispatch_method_hooks(NSInvocation *inv, SEL aliasSel) {
    if (!g_method_hooks) {
        inv.selector = aliasSel;
        [inv invoke];
        return;
    }

    PyGILState_STATE state = PyGILState_Ensure();

    id target = inv.target;
    SEL sel = inv.selector;
    Class cls = object_getClass(target);

    // Find the Python hook list by walking the class hierarchy.
    PyObject *hooks_list = NULL;
    Class probe = cls;
    while (probe && !hooks_list) {
        NSString *key = [NSString stringWithFormat:@"%s.%s",
                         class_getName(probe), sel_getName(sel)];
        PyObject *lst = PyDict_GetItemString(g_method_hooks, [key UTF8String]);
        if (lst && PyList_Check(lst) && PyList_Size(lst) > 0) hooks_list = lst;
        probe = class_getSuperclass(probe);
    }

    if (!hooks_list) {
        PyGILState_Release(state);
        inv.selector = aliasSel;
        [inv invoke];
        return;
    }

    // Keep object args alive across the Python detour.
    [inv retainArguments];

    // Build the MethodHookParam Python object.
    PyObject *param_cls = eg_method_hook_param_class();
    PyObject *param = param_cls ? PyObject_CallObject(param_cls, NULL) : NULL;
    if (!param) {
        PyErr_Clear();
        PyGILState_Release(state);
        // Couldn't build param — fall through and just call the original.
        inv.selector = aliasSel;
        [inv invoke];
        return;
    }

    // Marshal args[2:] into a Python list (idx 0/1 are self/_cmd).
    NSMethodSignature *sig = inv.methodSignature;
    NSUInteger argCount = sig.numberOfArguments;
    PyObject *args_list = PyList_New(0);
    for (NSUInteger i = 2; i < argCount; i++) {
        PyObject *py_arg = eg_invocation_arg_to_py(inv, i);
        PyList_Append(args_list, py_arg);
        Py_DECREF(py_arg);
    }

    PyObject *py_target = ns_to_py(target);
    PyObject_SetAttrString(param, "this_object", py_target);
    Py_DECREF(py_target);

    PyObject *py_method_name = PyUnicode_FromString(sel_getName(sel));
    PyObject_SetAttrString(param, "method", py_method_name);
    Py_DECREF(py_method_name);

    PyObject_SetAttrString(param, "args", args_list);

    // Fire `before` callbacks in registration order. Xposed/exteraGram semantics:
    // if any before sets a result (or asks to skip), the original method AND all
    // subsequent before/after callbacks are skipped.
    Py_ssize_t n = PyList_Size(hooks_list);
    BOOL skipOriginalAndAfter = NO;
    Py_ssize_t lastBeforeIdx = -1;
    for (Py_ssize_t i = 0; i < n; i++) {
        PyObject *hook = PyList_GetItem(hooks_list, i);  // borrowed
        if (!hook || !PyDict_Check(hook)) continue;
        PyObject *before = PyDict_GetItemString(hook, "before");
        if (before && before != Py_None) {
            PyObject *res = PyObject_CallOneArg(before, param);
            if (!res) { PyErr_Print(); PyErr_Clear(); }
            else Py_DECREF(res);
        }
        lastBeforeIdx = i;

        // After each before, check whether it set a result or asked to skip.
        PyObject *override = PyObject_GetAttrString(param, "_override_result");
        PyObject *skip = PyObject_GetAttrString(param, "_skip_original");
        BOOL hasOverride = (override && PyObject_IsTrue(override));
        BOOL hasSkip = (skip && PyObject_IsTrue(skip));
        Py_XDECREF(override);
        Py_XDECREF(skip);
        if (hasOverride || hasSkip) {
            skipOriginalAndAfter = YES;
            break;
        }
    }

    BOOL doSkip = skipOriginalAndAfter;

    // Write potentially-mutated args back into the invocation.
    PyObject *cur_args = PyObject_GetAttrString(param, "args");
    if (cur_args && PyList_Check(cur_args)) {
        Py_ssize_t avail = PyList_Size(cur_args);
        for (NSUInteger i = 2; i < argCount; i++) {
            Py_ssize_t pyIdx = (Py_ssize_t)(i - 2);
            if (pyIdx >= avail) break;
            PyObject *val = PyList_GetItem(cur_args, pyIdx);  // borrowed
            if (val) eg_apply_py_arg_to_invocation(inv, i, val, NO);
        }
    }
    Py_XDECREF(cur_args);

    // Invoke original.
    if (!doSkip) {
        inv.selector = aliasSel;
        Py_BEGIN_ALLOW_THREADS
        [inv invoke];
        Py_END_ALLOW_THREADS

        // Read return value into param.result.
        PyObject *ret_py = eg_invocation_return_to_py(inv);
        PyObject_SetAttrString(param, "result", ret_py);
        Py_DECREF(ret_py);
    }

    // Fire `after` callbacks in reverse order (Xposed semantics).
    // Skipped entirely if a before callback set the result / asked to skip.
    if (!skipOriginalAndAfter) {
        for (Py_ssize_t i = n - 1; i >= 0; i--) {
            PyObject *hook = PyList_GetItem(hooks_list, i);
            if (!hook || !PyDict_Check(hook)) continue;
            PyObject *after = PyDict_GetItemString(hook, "after");
            if (after && after != Py_None) {
                PyObject *res = PyObject_CallOneArg(after, param);
                if (!res) { PyErr_Print(); PyErr_Clear(); }
                else Py_DECREF(res);
            }
        }
    }
    (void)lastBeforeIdx;

    // Apply overridden return value, if any.
    PyObject *override = PyObject_GetAttrString(param, "_override_result");
    if (override && PyObject_IsTrue(override)) {
        PyObject *final_result = PyObject_GetAttrString(param, "result");
        if (final_result) {
            eg_apply_py_arg_to_invocation(inv, 0, final_result, YES);
            Py_DECREF(final_result);
        }
    }
    Py_XDECREF(override);

    Py_DECREF(args_list);
    Py_DECREF(param);

    PyGILState_Release(state);
}

// add_method_hook(class_name, selector, before, after) -> bool
static PyObject *py_add_method_hook(PyObject *self, PyObject *args) {
    const char *className = NULL;
    const char *selName = NULL;
    PyObject *before = Py_None;
    PyObject *after  = Py_None;
    if (!PyArg_ParseTuple(args, "ss|OO", &className, &selName, &before, &after)) return NULL;

    if ((before == Py_None || !PyCallable_Check(before)) &&
        (after  == Py_None || !PyCallable_Check(after))) {
        PyErr_SetString(PyExc_ValueError, "at least one of `before` or `after` must be callable");
        return NULL;
    }
    if (before != Py_None && !PyCallable_Check(before)) {
        PyErr_SetString(PyExc_TypeError, "`before` must be callable or None");
        return NULL;
    }
    if (after != Py_None && !PyCallable_Check(after)) {
        PyErr_SetString(PyExc_TypeError, "`after` must be callable or None");
        return NULL;
    }

    Class cls = objc_getClass(className);
    if (!cls) {
        plugin_log(@"PluginEngine", @"add_method_hook: class '%s' not found", className);
        Py_RETURN_FALSE;
    }
    SEL sel = sel_registerName(selName);
    if (!class_getInstanceMethod(cls, sel)) {
        plugin_log(@"PluginEngine", @"add_method_hook: -[%s %s] not found", className, selName);
        Py_RETURN_FALSE;
    }

    if (!g_method_hooks) g_method_hooks = PyDict_New();

    // Append { "before": before, "after": after } to the per-(cls, sel) list.
    NSString *key = [NSString stringWithFormat:@"%s.%s", className, selName];
    PyObject *list = PyDict_GetItemString(g_method_hooks, [key UTF8String]);
    BOOL firstTime = NO;
    if (!list) {
        list = PyList_New(0);
        PyDict_SetItemString(g_method_hooks, [key UTF8String], list);
        Py_DECREF(list);
        list = PyDict_GetItemString(g_method_hooks, [key UTF8String]);
        firstTime = YES;
    }
    PyObject *entry = PyDict_New();
    PyDict_SetItemString(entry, "before", before);
    PyDict_SetItemString(entry, "after",  after);
    PyList_Append(list, entry);
    Py_DECREF(entry);

    // First hook for this (cls, sel): install the trampoline.
    if (firstTime) {
        Py_BEGIN_ALLOW_THREADS
        [EGObjCSwizzler installForwardHookOnClass:cls selector:sel
                                          invoker:^(NSInvocation *inv, SEL aliasSel) {
            eg_dispatch_method_hooks(inv, aliasSel);
        }];
        Py_END_ALLOW_THREADS
    }

    Py_RETURN_TRUE;
}

static PyMethodDef ios_bridge_methods[] = {
    {"log_text",           py_log_text,           METH_VARARGS, "log_text(msg, tag='Plugin')"},
    {"add_tl_hook",        py_add_tl_hook,        METH_VARARGS, "add_tl_hook(tl_type, callback)"},
    {"add_method_hook",    py_add_method_hook,    METH_VARARGS, "add_method_hook(class_name, selector, before=None, after=None) -> bool"},
    {"has_hook",           py_has_hook,           METH_VARARGS, "has_hook(tl_type) -> bool"},
    {"run_on_main_thread", py_run_on_main_thread, METH_VARARGS, "run_on_main_thread(fn)"},
    {"show_alert",         py_show_alert,         METH_VARARGS, "show_alert(title, message, button='OK')"},
    {"show_toast",         py_show_toast,         METH_VARARGS, "show_toast(message, duration=2.0)"},
    {"copy_to_clipboard",  py_copy_to_clipboard,  METH_VARARGS, "copy_to_clipboard(text)"},
    {"open_url",           py_open_url,           METH_VARARGS, "open_url(url)"},
    {"haptic_feedback",    py_haptic_feedback,    METH_VARARGS, "haptic_feedback(style='medium')"},
    {"get_locale_language",py_get_locale_language,METH_NOARGS,  "get_locale_language() -> str"},
    {"get_string",         py_get_string,         METH_VARARGS, "get_string(key, default='') -> str"},
    {"get_plugin_setting", py_get_plugin_setting, METH_VARARGS, "get_plugin_setting(plugin_id, key, default=None) -> Any"},
    {"set_plugin_setting", py_set_plugin_setting, METH_VARARGS, "set_plugin_setting(plugin_id, key, value)"},
    {"get_plugin_data_dir",py_get_plugin_data_dir,METH_VARARGS, "get_plugin_data_dir(plugin_id) -> str"},
    {"get_account_id",     py_get_account_id,     METH_NOARGS,  "get_account_id() -> int"},
    {"get_user_id",        py_get_user_id,        METH_NOARGS,  "get_user_id() -> int"},
    {"get_connection_state",py_get_connection_state,METH_NOARGS,"get_connection_state() -> str"},
    {"kvc_get",            py_kvc_get,            METH_VARARGS, "kvc_get(obj_or_capsule, key) -> Any"},
    {"kvc_set",            py_kvc_set,            METH_VARARGS, "kvc_set(obj_or_capsule, key, value)"},
    {"objc_class_name",    py_objc_class_name,    METH_VARARGS, "objc_class_name(obj_or_capsule) -> str"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef ios_bridge_module = {
    PyModuleDef_HEAD_INIT, "_ios_bridge", NULL, -1, ios_bridge_methods
};

PyMODINIT_FUNC PyInit__ios_bridge(void) {
    PyObject *m = PyModule_Create(&ios_bridge_module);
    if (!m) return NULL;
    // Expose the global hook dict so Python code can inspect it if needed
    if (g_tl_hooks) PyModule_AddObject(m, "_hooks", g_tl_hooks);
    return m;
}

// ---------------------------------------------------------------------------
// ObjC object wrapping (PyCapsule + hook_utils.ObjCObject)
// ---------------------------------------------------------------------------
//
// Non-primitive ObjC values that flow into Python (hook args, return values,
// KVC reads) are wrapped as hook_utils.ObjCObject. The wrapper holds a
// PyCapsule that stores a +1-retained `id`; the capsule's destructor releases
// the retain when the wrapper is garbage-collected.
//
// Forward declarations for ns_to_py / py_to_ns (defined further below).
static PyObject *ns_to_py(id obj);
static id py_to_ns(PyObject *obj);

static PyObject *eg_objcobject_class_cached = NULL;

static PyObject *eg_get_objcobject_class(void) {
    if (eg_objcobject_class_cached) return eg_objcobject_class_cached;
    PyObject *mod = PyImport_ImportModule("hook_utils");
    if (!mod) { PyErr_Clear(); return NULL; }
    PyObject *cls = PyObject_GetAttrString(mod, "ObjCObject");
    Py_DECREF(mod);
    if (!cls) { PyErr_Clear(); return NULL; }
    eg_objcobject_class_cached = cls;  // keep strong ref
    return cls;
}

// PyCapsule destructor: releases the +1 retain taken at creation time.
static void eg_objcref_capsule_destructor(PyObject *capsule) {
    void *p = PyCapsule_GetPointer(capsule, "egobjc");
    if (p) CFRelease(p);
}

// Wrap an ObjC object as hook_utils.ObjCObject(PyCapsule, class_name).
// Takes +1 retain so the wrapper owns a strong reference.
static PyObject *eg_wrap_as_objcobject(id obj) {
    if (!obj) Py_RETURN_NONE;
    PyObject *cls = eg_get_objcobject_class();
    if (!cls) {
        // Bridge isn't fully wired yet — fall back to repr string.
        return PyUnicode_FromString([[obj description] UTF8String]);
    }
    void *retained = (void *)CFBridgingRetain(obj);  // +1
    PyObject *capsule = PyCapsule_New(retained, "egobjc", eg_objcref_capsule_destructor);
    if (!capsule) {
        CFRelease(retained);
        PyErr_Clear();
        return PyUnicode_FromString([[obj description] UTF8String]);
    }
    PyObject *className = PyUnicode_FromString(object_getClassName(obj));
    PyObject *argTuple = PyTuple_Pack(2, capsule, className);
    Py_DECREF(capsule); Py_DECREF(className);
    PyObject *instance = PyObject_CallObject(cls, argTuple);
    Py_DECREF(argTuple);
    if (!instance) { PyErr_Clear(); Py_RETURN_NONE; }
    return instance;
}

// Inverse of eg_wrap_as_objcobject. Returns nil if `obj` isn't an ObjCObject
// (or if its capsule is gone). The returned id is autorelease-lifetime;
// callers that need to retain it must do so explicitly.
static id eg_unwrap_objcobject(PyObject *obj) {
    if (!obj || obj == Py_None) return nil;
    PyObject *cls = eg_get_objcobject_class();
    if (!cls) return nil;
    if (PyObject_IsInstance(obj, cls) != 1) { PyErr_Clear(); return nil; }
    PyObject *capsule = PyObject_GetAttrString(obj, "_capsule");
    if (!capsule) { PyErr_Clear(); return nil; }
    id result = nil;
    if (PyCapsule_CheckExact(capsule)) {
        void *p = PyCapsule_GetPointer(capsule, "egobjc");
        if (p) result = (__bridge id)p;
    }
    Py_DECREF(capsule);
    return result;
}

// kvc_get(obj_or_capsule, key) -> Any
//   obj_or_capsule: ObjCObject instance OR raw PyCapsule
//   key: NSString-coercible
// Performs [obj valueForKey:key] and wraps the result via ns_to_py.
static PyObject *py_kvc_get(PyObject *self, PyObject *args) {
    PyObject *first;
    const char *key;
    if (!PyArg_ParseTuple(args, "Os", &first, &key)) return NULL;

    id obj = nil;
    if (PyCapsule_CheckExact(first)) {
        void *p = PyCapsule_GetPointer(first, "egobjc");
        if (p) obj = (__bridge id)p;
    } else {
        obj = eg_unwrap_objcobject(first);
    }
    if (!obj) {
        PyErr_SetString(PyExc_AttributeError, "kvc_get: receiver is not an ObjC object");
        return NULL;
    }

    NSString *nsKey = [NSString stringWithUTF8String:key ?: ""];
    __block id value = nil;
    __block NSString *exReason = nil;
    @try {
        value = [obj valueForKey:nsKey];
    } @catch (NSException *ex) {
        exReason = ex.reason ?: @"unknown";
    }
    if (exReason) {
        PyErr_Format(PyExc_AttributeError, "kvc_get(%s): %s", key, [exReason UTF8String]);
        return NULL;
    }
    return ns_to_py(value);
}

// kvc_set(obj_or_capsule, key, value)
static PyObject *py_kvc_set(PyObject *self, PyObject *args) {
    PyObject *first, *value;
    const char *key;
    if (!PyArg_ParseTuple(args, "OsO", &first, &key, &value)) return NULL;

    id obj = nil;
    if (PyCapsule_CheckExact(first)) {
        void *p = PyCapsule_GetPointer(first, "egobjc");
        if (p) obj = (__bridge id)p;
    } else {
        obj = eg_unwrap_objcobject(first);
    }
    if (!obj) {
        PyErr_SetString(PyExc_AttributeError, "kvc_set: receiver is not an ObjC object");
        return NULL;
    }

    id ns_value = py_to_ns(value);
    if (ns_value == [NSNull null]) ns_value = nil;

    NSString *nsKey = [NSString stringWithUTF8String:key ?: ""];
    __block NSString *exReason = nil;
    @try {
        [obj setValue:ns_value forKey:nsKey];
    } @catch (NSException *ex) {
        exReason = ex.reason ?: @"unknown";
    }
    if (exReason) {
        PyErr_Format(PyExc_AttributeError, "kvc_set(%s): %s", key, [exReason UTF8String]);
        return NULL;
    }
    Py_RETURN_NONE;
}

// objc_class_name(obj_or_capsule) -> str  (empty string on failure)
static PyObject *py_objc_class_name(PyObject *self, PyObject *args) {
    PyObject *first;
    if (!PyArg_ParseTuple(args, "O", &first)) return NULL;
    id obj = nil;
    if (PyCapsule_CheckExact(first)) {
        void *p = PyCapsule_GetPointer(first, "egobjc");
        if (p) obj = (__bridge id)p;
    } else {
        obj = eg_unwrap_objcobject(first);
    }
    return PyUnicode_FromString(obj ? object_getClassName(obj) : "");
}

// ---------------------------------------------------------------------------
// Helpers: NSObject ↔ PyObject conversion
// ---------------------------------------------------------------------------

static PyObject *ns_to_py(id obj) {
    if (!obj || obj == [NSNull null]) Py_RETURN_NONE;
    if ([obj isKindOfClass:[NSString class]]) {
        return PyUnicode_FromString([(NSString *)obj UTF8String]);
    }
    if ([obj isKindOfClass:[NSNumber class]]) {
        NSNumber *n = obj;
        if (strcmp(n.objCType, @encode(BOOL)) == 0 ||
            strcmp(n.objCType, @encode(bool)) == 0) {
            return PyBool_FromLong(n.boolValue ? 1 : 0);
        }
        // Check if it's a float
        CFNumberType type = CFNumberGetType((CFNumberRef)n);
        if (type == kCFNumberFloat32Type || type == kCFNumberFloat64Type ||
            type == kCFNumberDoubleType  || type == kCFNumberFloatType) {
            return PyFloat_FromDouble(n.doubleValue);
        }
        return PyLong_FromLongLong(n.longLongValue);
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSArray *arr = obj;
        PyObject *list = PyList_New((Py_ssize_t)arr.count);
        for (NSUInteger i = 0; i < arr.count; i++) {
            PyObject *item = ns_to_py(arr[i]);
            PyList_SET_ITEM(list, (Py_ssize_t)i, item);
        }
        return list;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = obj;
        PyObject *py_dict = PyDict_New();
        for (id key in dict) {
            PyObject *py_key = ns_to_py(key);
            PyObject *py_val = ns_to_py(dict[key]);
            PyDict_SetItem(py_dict, py_key, py_val);
            Py_DECREF(py_key);
            Py_DECREF(py_val);
        }
        return py_dict;
    }
    // Fallback: wrap as hook_utils.ObjCObject so plugins can KVC into it.
    return eg_wrap_as_objcobject(obj);
}

static id py_to_ns(PyObject *obj) {
    if (!obj || obj == Py_None) return [NSNull null];
    // ObjCObject → unwrap to the underlying id.
    id unwrapped = eg_unwrap_objcobject(obj);
    if (unwrapped) return unwrapped;
    if (PyBool_Check(obj)) return @((BOOL)(obj == Py_True));
    if (PyLong_Check(obj)) return @(PyLong_AsLongLong(obj));
    if (PyFloat_Check(obj)) return @(PyFloat_AsDouble(obj));
    if (PyUnicode_Check(obj)) {
        const char *s = PyUnicode_AsUTF8(obj);
        return s ? [NSString stringWithUTF8String:s] : @"";
    }
    if (PyList_Check(obj) || PyTuple_Check(obj)) {
        Py_ssize_t n = PySequence_Size(obj);
        NSMutableArray *arr = [NSMutableArray arrayWithCapacity:(NSUInteger)n];
        for (Py_ssize_t i = 0; i < n; i++) {
            PyObject *item = PySequence_GetItem(obj, i);
            [arr addObject:py_to_ns(item)];
            Py_DECREF(item);
        }
        return arr;
    }
    if (PyDict_Check(obj)) {
        PyObject *keys = PyDict_Keys(obj);
        Py_ssize_t n = PyList_Size(keys);
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)n];
        for (Py_ssize_t i = 0; i < n; i++) {
            PyObject *key = PyList_GetItem(keys, i);
            PyObject *val = PyDict_GetItem(obj, key);
            id nsKey = py_to_ns(key);
            id nsVal = py_to_ns(val);
            if (nsKey && nsVal) dict[nsKey] = nsVal;
        }
        Py_DECREF(keys);
        return dict;
    }
    return [[NSString alloc] initWithFormat:@"<PyObj:%s>",
            Py_TYPE(obj)->tp_name];
}

#endif // EGPLUGIN_HAS_PYTHON

// ---------------------------------------------------------------------------
// EGPythonBridge implementation
// ---------------------------------------------------------------------------

@implementation EGPythonBridge

+ (BOOL)initializeWithHome:(NSString *)pythonHome
                   sdkPath:(NSString *)sdkPath
               pluginsPath:(NSString *)pluginsPath
          sitePackagesPath:(NSString *)sitePkgs {
#if EGPLUGIN_HAS_PYTHON
    if (g_initialized) return YES;

    NSAssert([NSThread isMainThread], @"EGPythonBridge: initializeWithHome must be called on the main thread");

    // dispatch_once guarantees exactly-once execution and blocks concurrent callers
    // until the block finishes.  This prevents the PyImport_AppendInittab-after-
    // Py_Initialize fatal error that Python 3.14 raises on double-init attempts.
    static dispatch_once_t s_pythonOnce = 0;
    dispatch_once(&s_pythonOnce, ^{
        // Safety net: detect if Python was somehow started by another path.
        if (Py_IsInitialized()) {
            plugin_log(@"PluginEngine", @"Python already running — adopting existing state");
            PyGILState_STATE s = PyGILState_Ensure();
            if (!g_tl_hooks)       g_tl_hooks       = PyDict_New();
            if (!g_loaded_modules) g_loaded_modules  = PyDict_New();
            if (!g_method_hooks)   g_method_hooks   = PyDict_New();
            PyGILState_Release(s);
            g_initialized = YES;
            return;
        }

        // Register C extension BEFORE any initialization (required by CPython).
        PyImport_AppendInittab("_ios_bridge", &PyInit__ios_bridge);

        // ---------------------------------------------------------------------------
        // Python 3.14: use modern PyConfig API (replaces Py_Initialize() for embeds)
        // ---------------------------------------------------------------------------
        PyPreConfig preconfig;
        PyPreConfig_InitIsolatedConfig(&preconfig);
        preconfig.utf8_mode = 1;

        PyStatus status = Py_PreInitialize(&preconfig);
        if (PyStatus_Exception(status)) {
            plugin_log(@"PluginEngine", @"Py_PreInitialize failed: %s", status.err_msg);
            char buf[512]; snprintf(buf, sizeof(buf), "Py_PreInitialize failed: %s", status.err_msg ?: "(null)");
            EGPluginDebugLog_appendCStr("Runtime", buf);
            return;
        }

        PyConfig config;
        PyConfig_InitIsolatedConfig(&config);
        config.write_bytecode = 0;        // can't modify signed bundle
        config.install_signal_handlers = 1;
        config.use_system_logger = 1;     // stdout/stderr → os_log

        // Set PYTHONHOME (tells CPython where lib/python3.14 lives)
        wchar_t *wHome = Py_DecodeLocale([pythonHome UTF8String], NULL);
        if (wHome) {
            status = PyConfig_SetString(&config, &config.home, wHome);
            PyMem_RawFree(wHome);
            if (PyStatus_Exception(status)) {
                plugin_log(@"PluginEngine", @"PyConfig_SetString(home) failed: %s", status.err_msg);
                char buf[512]; snprintf(buf, sizeof(buf), "PyConfig_SetString(home) failed: %s", status.err_msg ?: "(null)");
                EGPluginDebugLog_appendCStr("Runtime", buf);
                PyConfig_Clear(&config);
                return;
            }
        }

        // Read stdlib paths from config.home before adding extras
        status = PyConfig_Read(&config);
        if (PyStatus_Exception(status)) {
            plugin_log(@"PluginEngine", @"PyConfig_Read failed: %s", status.err_msg);
            char buf[512]; snprintf(buf, sizeof(buf), "PyConfig_Read failed: %s", status.err_msg ?: "(null)");
            EGPluginDebugLog_appendCStr("Runtime", buf);
            PyConfig_Clear(&config);
            return;
        }

        // Do NOT set module_search_paths_set=1 — that would replace the computed stdlib
        // paths with only our extras, causing "Failed to import encodings module".
        // Instead, let CPython compute sys.path from home automatically and append
        // our extra paths to sys.path after initialization via the C API.

        @try {
            status = Py_InitializeFromConfig(&config);
        } @catch (NSException *ex) {
            PyConfig_Clear(&config);
            plugin_log(@"PluginEngine", @"Py_InitializeFromConfig exception: %@", ex.reason);
            EGPluginDebugLog_appendCStr("Runtime", [[NSString stringWithFormat:@"Py_InitializeFromConfig exception: %@", ex.reason] UTF8String]);
            return;
        }
        PyConfig_Clear(&config);

        if (PyStatus_Exception(status)) {
            plugin_log(@"PluginEngine", @"Py_InitializeFromConfig failed: %s", status.err_msg);
            char buf[512]; snprintf(buf, sizeof(buf), "Py_InitializeFromConfig failed: %s", status.err_msg ?: "(null)");
            EGPluginDebugLog_appendCStr("Runtime", buf);
            return;
        }

        // Release GIL (allows GILState acquire/release pattern on all threads)
        PyEval_SaveThread();

        // One-time global state setup + extend sys.path with extra dirs
        PyGILState_STATE state = PyGILState_Ensure();
        g_tl_hooks = PyDict_New();
        g_loaded_modules = PyDict_New();
        g_method_hooks = PyDict_New();

        // Append SDK, plugins, and site-packages to sys.path now that Python is alive.
        PyObject *sysPath = PySys_GetObject("path"); // borrowed ref — never NULL post-init
        if (sysPath) {
            NSArray<NSString *> *extraPaths = @[sdkPath, pluginsPath, sitePkgs];
            for (NSString *p in extraPaths) {
                if (p.length == 0) continue;
                PyObject *pyPath = PyUnicode_FromString([p UTF8String]);
                if (pyPath) { PyList_Append(sysPath, pyPath); Py_DECREF(pyPath); }
            }
        }
        PyGILState_Release(state);

        g_initialized = YES;
        plugin_log(@"PluginEngine", @"CPython %s ready. home=%@", PY_VERSION, pythonHome);
    });

    return g_initialized;
#else
    (void)pythonHome; (void)sdkPath; (void)pluginsPath; (void)sitePkgs;
    plugin_log(@"PluginEngine", @"Python.xcframework not present — engine disabled");
    return NO;
#endif
}

+ (BOOL)isInitialized {
#if EGPLUGIN_HAS_PYTHON
    return g_initialized;
#else
    return NO;
#endif
}

+ (void)withPython:(NS_NOESCAPE void (^)(void))block {
#if EGPLUGIN_HAS_PYTHON
    if (!g_initialized) return;
    PyGILState_STATE state = PyGILState_Ensure();
    block();
    PyGILState_Release(state);
#endif
}

+ (nullable NSString *)loadPlugin:(NSString *)pluginId fromPath:(NSString *)path {
#if EGPLUGIN_HAS_PYTHON
    if (!g_initialized) return @"Python runtime not initialized";
    __block NSString *errorMsg = nil;
    [self withPython:^{
        PyObject *importlib_util     = PyImport_ImportModule("importlib.util");
        PyObject *importlib_machinery = PyImport_ImportModule("importlib.machinery");
        if (!importlib_util || !importlib_machinery) {
            PyErr_Clear();
            Py_XDECREF(importlib_util); Py_XDECREF(importlib_machinery);
            errorMsg = @"importlib not available";
            return;
        }

        // .plugin is not a recognised extension — build an explicit SourceFileLoader
        // so spec_from_file_location knows how to handle the file.
        PyObject *SFL = PyObject_GetAttrString(importlib_machinery, "SourceFileLoader");
        if (!SFL) {
            PyErr_Clear(); Py_DECREF(importlib_util); Py_DECREF(importlib_machinery);
            errorMsg = @"SourceFileLoader not found";
            return;
        }
        PyObject *loader = PyObject_CallFunction(SFL, "ss", pluginId.UTF8String, path.UTF8String);
        Py_DECREF(SFL);
        if (!loader) {
            PyErr_Clear(); Py_DECREF(importlib_util); Py_DECREF(importlib_machinery);
            errorMsg = @"SourceFileLoader() failed";
            return;
        }

        // spec_from_file_location(name, path, loader=loader)
        PyObject *kwArgs = PyDict_New();
        PyDict_SetItemString(kwArgs, "loader", loader);
        Py_DECREF(loader); loader = NULL;

        PyObject *posArgs = PyTuple_Pack(2,
            PyUnicode_FromString(pluginId.UTF8String),
            PyUnicode_FromString(path.UTF8String));
        PyObject *sflFn = PyObject_GetAttrString(importlib_util, "spec_from_file_location");
        PyObject *spec = sflFn ? PyObject_Call(sflFn, posArgs, kwArgs) : NULL;
        Py_XDECREF(sflFn);
        Py_DECREF(posArgs); Py_DECREF(kwArgs);

        if (!spec || spec == Py_None) {
            PyErr_Clear();
            Py_XDECREF(spec);
            Py_DECREF(importlib_util); Py_DECREF(importlib_machinery);
            errorMsg = [NSString stringWithFormat:@"spec_from_file_location failed for %@", path];
            return;
        }
        Py_DECREF(importlib_machinery);

        PyObject *module = PyObject_CallMethod(importlib_util, "module_from_spec", "O", spec);
        if (!module) {
            PyErr_Clear(); Py_DECREF(spec); Py_DECREF(importlib_util);
            errorMsg = @"module_from_spec failed";
            return;
        }

        // Register in sys.modules so imports within the plugin work
        PyObject *sys_modules = PySys_GetObject("modules"); // borrowed
        PyDict_SetItemString(sys_modules, pluginId.UTF8String, module);

        // --- Metadata validation (AST, pre-exec) ---
        // `__os__` must be a bare lowercase identifier `ios` — NOT a quoted string.
        // This is a metadata directive, parsed syntactically like Android exteraGram
        // does, not a Python value. Anything else → refuse to load.
        {
            static const char *validatorSrc =
                "import ast\n"
                "def _eg_validate(_path):\n"
                "    try:\n"
                "        with open(_path, 'r') as _f:\n"
                "            _tree = ast.parse(_f.read())\n"
                "    except Exception as _e:\n"
                "        return 'failed to parse plugin source: ' + str(_e)\n"
                "    for _node in _tree.body:\n"
                "        if not isinstance(_node, ast.Assign):\n"
                "            continue\n"
                "        for _t in _node.targets:\n"
                "            if isinstance(_t, ast.Name) and _t.id == '__os__':\n"
                "                _v = _node.value\n"
                "                if isinstance(_v, ast.Name) and _v.id == 'ios':\n"
                "                    return 'ok'\n"
                "                if isinstance(_v, ast.Constant):\n"
                "                    return 'plugin __os__ must be a bare identifier (ios), not a string literal'\n"
                "                return 'plugin __os__ has unsupported form (must be: __os__ = ios)'\n"
                "    return 'plugin metadata is missing __os__ = ios'\n";

            PyObject *vGlobals = PyDict_New();
            PyDict_SetItemString(vGlobals, "__builtins__", PyEval_GetBuiltins());
            PyObject *vCompiled = PyRun_String(validatorSrc, Py_file_input, vGlobals, vGlobals);
            NSString *validation = nil;
            if (vCompiled) {
                Py_DECREF(vCompiled);
                PyObject *vFn = PyDict_GetItemString(vGlobals, "_eg_validate");
                PyObject *vResult = vFn ? PyObject_CallFunction(vFn, "s", path.UTF8String) : NULL;
                if (vResult && PyUnicode_Check(vResult)) {
                    const char *s = PyUnicode_AsUTF8(vResult);
                    if (s) validation = [NSString stringWithUTF8String:s];
                }
                Py_XDECREF(vResult);
            }
            Py_DECREF(vGlobals);
            if (!validation) {
                PyErr_Clear();
                validation = @"metadata validator failed";
            }
            if (![validation isEqualToString:@"ok"]) {
                errorMsg = validation;
                PyDict_DelItemString(sys_modules, pluginId.UTF8String);
                Py_DECREF(module); Py_DECREF(spec); Py_DECREF(importlib_util);
                plugin_log(@"PluginEngine", @"Refused to load plugin %@: %@", pluginId, validation);
                return;
            }

            // Inject `ios` as a sentinel string in the module's globals so that the
            // bare-identifier assignment `__os__ = ios` doesn't NameError at exec.
            PyObject *modDict = PyModule_GetDict(module);  // borrowed
            if (modDict) {
                PyObject *iosStr = PyUnicode_FromString("ios");
                PyDict_SetItemString(modDict, "ios", iosStr);
                Py_DECREF(iosStr);
            }
        }

        // Execute the module body
        PyObject *specLoader = PyObject_GetAttrString(spec, "loader");
        PyObject *exec_result = specLoader ? PyObject_CallMethod(specLoader, "exec_module", "O", module) : NULL;
        Py_XDECREF(specLoader);

        if (!exec_result) {
            // Capture traceback as error string
            PyObject *exc = PyErr_GetRaisedException();
            if (exc) {
                PyObject *str = PyObject_Str(exc);
                const char *cstr = str ? PyUnicode_AsUTF8(str) : "unknown error";
                errorMsg = [NSString stringWithUTF8String:cstr ?: "unknown error"];
                Py_XDECREF(str);
                Py_DECREF(exc);
            } else {
                errorMsg = @"exec_module failed";
            }
            PyDict_DelItemString(sys_modules, pluginId.UTF8String);
            Py_DECREF(module); Py_DECREF(spec); Py_DECREF(importlib_util);
            return;
        }
        Py_DECREF(exec_result);

        // ---------------------------------------------------------------------
        // Lifecycle dispatch. Two supported forms:
        //   (a) Android-style: a subclass of base_plugin.Plugin/BasePlugin is
        //       defined at module level. The loader instantiates it and calls
        //       on_plugin_load(); the instance is stashed at module.__eg_instance__
        //       so unloadPlugin: can call on_plugin_unload().
        //   (b) Legacy iOS-style: a module-level function `on_load(module)`.
        // The class-based path wins when both are present.
        // ---------------------------------------------------------------------

        PyObject *plugin_instance = NULL;
        {
            PyObject *base_plugin_mod = PyImport_ImportModule("base_plugin");
            PyObject *plugin_base = base_plugin_mod
                ? PyObject_GetAttrString(base_plugin_mod, "Plugin") : NULL;
            Py_XDECREF(base_plugin_mod);
            if (plugin_base) {
                PyObject *modDict = PyModule_GetDict(module);  // borrowed
                PyObject *key, *value;
                Py_ssize_t pos = 0;
                while (PyDict_Next(modDict, &pos, &key, &value)) {
                    if (!PyType_Check(value)) continue;
                    if (value == plugin_base) continue;  // skip the base itself
                    int isSub = PyObject_IsSubclass(value, plugin_base);
                    if (isSub != 1) { if (isSub < 0) PyErr_Clear(); continue; }
                    plugin_instance = PyObject_CallObject(value, NULL);
                    if (plugin_instance) {
                        PyObject_SetAttrString(module, "__eg_instance__", plugin_instance);
                        break;
                    }
                    PyErr_Print(); PyErr_Clear();
                }
                Py_DECREF(plugin_base);
            } else {
                PyErr_Clear();
            }
        }

        if (plugin_instance) {
            // Prefer on_plugin_load (Android), fall back to on_load (iOS-native).
            PyObject *opl = PyObject_GetAttrString(plugin_instance, "on_plugin_load");
            if (opl && PyCallable_Check(opl)) {
                PyObject *r = PyObject_CallNoArgs(opl);
                if (!r) { PyErr_Print(); PyErr_Clear(); }
                else Py_DECREF(r);
            } else {
                PyErr_Clear();
                PyObject *ol = PyObject_GetAttrString(plugin_instance, "on_load");
                if (ol && PyCallable_Check(ol)) {
                    PyObject *r = PyObject_CallNoArgs(ol);
                    if (!r) { PyErr_Print(); PyErr_Clear(); }
                    else Py_DECREF(r);
                }
                Py_XDECREF(ol);
            }
            Py_XDECREF(opl);
            Py_DECREF(plugin_instance);
        } else {
            // Legacy form: module-level on_load(module).
            PyObject *on_load = PyObject_GetAttrString(module, "on_load");
            if (on_load && PyCallable_Check(on_load)) {
                PyObject *r = PyObject_CallFunctionObjArgs(on_load, module, NULL);
                if (!r) { PyErr_Print(); PyErr_Clear(); }
                else Py_DECREF(r);
            }
            PyErr_Clear();
            Py_XDECREF(on_load);
        }

        // Store loaded module
        PyDict_SetItemString(g_loaded_modules, pluginId.UTF8String, module);

        Py_DECREF(module);
        Py_DECREF(spec);
        Py_DECREF(importlib_util);

        plugin_log(@"PluginEngine", @"Loaded plugin: %@", pluginId);
    }];
    return errorMsg;
#else
    return @"Python not available";
#endif
}

+ (void)unloadPlugin:(NSString *)pluginId {
#if EGPLUGIN_HAS_PYTHON
    if (!g_initialized) return;
    [self withPython:^{
        PyObject *module = PyDict_GetItemString(g_loaded_modules, pluginId.UTF8String);
        if (module) {
            // Mirror loadPlugin lifecycle: prefer instance.on_plugin_unload,
            // then instance.on_unload, then module-level on_unload().
            PyObject *instance = PyObject_GetAttrString(module, "__eg_instance__");
            if (instance && instance != Py_None) {
                PyObject *opu = PyObject_GetAttrString(instance, "on_plugin_unload");
                if (opu && PyCallable_Check(opu)) {
                    PyObject *r = PyObject_CallNoArgs(opu);
                    if (!r) { PyErr_Print(); PyErr_Clear(); }
                    else Py_DECREF(r);
                } else {
                    PyErr_Clear();
                    PyObject *ou = PyObject_GetAttrString(instance, "on_unload");
                    if (ou && PyCallable_Check(ou)) {
                        PyObject *r = PyObject_CallNoArgs(ou);
                        if (!r) { PyErr_Print(); PyErr_Clear(); }
                        else Py_DECREF(r);
                    }
                    Py_XDECREF(ou);
                }
                Py_XDECREF(opu);
                Py_DECREF(instance);
                PyObject_DelAttrString(module, "__eg_instance__");
                PyErr_Clear();
            } else {
                Py_XDECREF(instance);
                PyErr_Clear();
                PyObject *on_unload = PyObject_GetAttrString(module, "on_unload");
                if (on_unload && PyCallable_Check(on_unload)) {
                    PyObject *r = PyObject_CallFunctionObjArgs(on_unload, NULL);
                    if (!r) { PyErr_Print(); PyErr_Clear(); }
                    else Py_DECREF(r);
                }
                PyErr_Clear();
                Py_XDECREF(on_unload);
            }
            PyDict_DelItemString(g_loaded_modules, pluginId.UTF8String);
            // Remove from sys.modules
            PyObject *sys_modules = PySys_GetObject("modules");
            PyDict_DelItemString(sys_modules, pluginId.UTF8String);
        }
    }];
#endif
}

+ (void)dispatchTLHook:(NSString *)tlType params:(NSMutableDictionary<NSString *, id> *)params {
#if EGPLUGIN_HAS_PYTHON
    if (!g_initialized || !g_tl_hooks) return;
    [self withPython:^{
        PyObject *list = PyDict_GetItemString(g_tl_hooks, tlType.UTF8String);
        if (!list || PyList_Size(list) == 0) return;

        // Convert params to a Python dict
        PyObject *py_params = ns_to_py(params);

        Py_ssize_t n = PyList_Size(list);
        for (Py_ssize_t i = 0; i < n; i++) {
            PyObject *cb = PyList_GetItem(list, i); // borrowed
            PyObject *result = PyObject_CallFunctionObjArgs(cb, py_params, NULL);
            if (!result) { PyErr_Clear(); } else { Py_DECREF(result); }
        }

        // Write modified values back to params
        PyObject *keys = PyDict_Keys(py_params);
        Py_ssize_t kn = PyList_Size(keys);
        for (Py_ssize_t i = 0; i < kn; i++) {
            PyObject *key = PyList_GetItem(keys, i);
            PyObject *val = PyDict_GetItem(py_params, key);
            id nsKey = py_to_ns(key);
            id nsVal = py_to_ns(val);
            if (nsKey && ![nsKey isKindOfClass:[NSNull class]]) {
                params[nsKey] = nsVal;
            }
        }
        Py_DECREF(keys);
        Py_DECREF(py_params);
    }];
#endif
}

+ (BOOL)hasHook:(NSString *)tlType {
#if EGPLUGIN_HAS_PYTHON
    if (!g_initialized || !g_tl_hooks) return NO;
    __block BOOL result = NO;
    [self withPython:^{
        PyObject *list = PyDict_GetItemString(g_tl_hooks, tlType.UTF8String);
        result = (list && PyList_Size(list) > 0);
    }];
    return result;
#else
    return NO;
#endif
}

+ (void)logFromPlugin:(NSString *)tag message:(NSString *)message {
    // Forward to Swift EGLoggerBridge via notification or direct call.
    // Using NSNotification avoids a direct Swift import from ObjC.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"EGPluginLogNotification"
                          object:nil
                        userInfo:@{@"tag": tag, @"msg": message}];
    });
}

+ (BOOL)extractPythonStdlibZip:(NSString *)zipPath toDirectory:(NSString *)destDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    if (![fm createDirectoryAtPath:destDir
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&err]) {
        plugin_log(@"PluginEngine", @"Could not create stdlib dir %@: %@", destDir, err);
        return NO;
    }
    BOOL ok = [SSZipArchive unzipFileAtPath:zipPath toDestination:destDir];
    if (!ok) {
        plugin_log(@"PluginEngine", @"Failed to unzip %@ → %@", zipPath, destDir);
    }
    return ok;
}

@end
