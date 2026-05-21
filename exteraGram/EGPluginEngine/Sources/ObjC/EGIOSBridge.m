// MARK: exteraGram — EGPluginEngine ObjC/Python bridge implementation

#import "EGIOSBridge.h"
#import <UIKit/UIKit.h>
#import <os/log.h>
#import <ZipArchive/ZipArchive.h>

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

static PyMethodDef ios_bridge_methods[] = {
    {"log_text",           py_log_text,           METH_VARARGS, "log_text(msg, tag='Plugin')"},
    {"add_tl_hook",        py_add_tl_hook,        METH_VARARGS, "add_tl_hook(tl_type, callback)"},
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
    // Fallback: repr string
    return PyUnicode_FromString([[obj description] UTF8String]);
}

static id py_to_ns(PyObject *obj) {
    if (!obj || obj == Py_None) return [NSNull null];
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

        // Call on_load(module) if it exists
        PyObject *on_load = PyObject_GetAttrString(module, "on_load");
        if (on_load && PyCallable_Check(on_load)) {
            PyObject *r = PyObject_CallFunctionObjArgs(on_load, module, NULL);
            if (!r) { PyErr_Clear(); } else { Py_DECREF(r); }
        }
        PyErr_Clear();
        Py_XDECREF(on_load);

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
            PyObject *on_unload = PyObject_GetAttrString(module, "on_unload");
            if (on_unload && PyCallable_Check(on_unload)) {
                PyObject *r = PyObject_CallFunctionObjArgs(on_unload, NULL);
                if (!r) PyErr_Clear(); else Py_DECREF(r);
            }
            PyErr_Clear();
            Py_XDECREF(on_unload);
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
