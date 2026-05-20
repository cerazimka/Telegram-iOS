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
    // Delay 0.5s so any presenting sheet / install flow can finish dismissing first.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
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
        while (root.presentedViewController) root = root.presentedViewController;
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

static PyMethodDef ios_bridge_methods[] = {
    {"log_text",           py_log_text,           METH_VARARGS, "log_text(msg, tag='Plugin')"},
    {"add_tl_hook",        py_add_tl_hook,        METH_VARARGS, "add_tl_hook(tl_type, callback)"},
    {"has_hook",           py_has_hook,           METH_VARARGS, "has_hook(tl_type) -> bool"},
    {"run_on_main_thread", py_run_on_main_thread, METH_VARARGS, "run_on_main_thread(fn)"},
    {"show_alert",         py_show_alert,         METH_VARARGS, "show_alert(title, message, button='OK')"},
    {"show_toast",         py_show_toast,         METH_VARARGS, "show_toast(message, duration=2.0)"},
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
        return NO;
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
            PyConfig_Clear(&config);
            return NO;
        }
    }

    // Read stdlib paths from config.home before adding extras
    status = PyConfig_Read(&config);
    if (PyStatus_Exception(status)) {
        plugin_log(@"PluginEngine", @"PyConfig_Read failed: %s", status.err_msg);
        PyConfig_Clear(&config);
        return NO;
    }

    // Append extra search paths (SDK, plugins, site-packages)
    NSArray<NSString *> *extraPaths = @[sdkPath, pluginsPath, sitePkgs];
    for (NSString *p in extraPaths) {
        if (p.length == 0) continue;
        wchar_t *wp = Py_DecodeLocale([p UTF8String], NULL);
        if (wp) {
            PyWideStringList_Append(&config.module_search_paths, wp);
            PyMem_RawFree(wp);
        }
    }
    config.module_search_paths_set = 1;

    @try {
        status = Py_InitializeFromConfig(&config);
    } @catch (NSException *ex) {
        PyConfig_Clear(&config);
        plugin_log(@"PluginEngine", @"Py_InitializeFromConfig exception: %@", ex.reason);
        return NO;
    }
    PyConfig_Clear(&config);

    if (PyStatus_Exception(status)) {
        plugin_log(@"PluginEngine", @"Py_InitializeFromConfig failed: %s", status.err_msg);
        return NO;
    }

    // Release GIL (allows GILState acquire/release pattern on all threads)
    PyEval_SaveThread();

    // One-time global state setup
    PyGILState_STATE state = PyGILState_Ensure();
    g_tl_hooks = PyDict_New();
    g_loaded_modules = PyDict_New();
    PyGILState_Release(state);

    g_initialized = YES;
    plugin_log(@"PluginEngine", @"CPython %s ready. home=%@", PY_VERSION, pythonHome);
    return YES;
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
        PyObject *importlib_util = PyImport_ImportModule("importlib.util");
        if (!importlib_util) { PyErr_Clear(); errorMsg = @"importlib.util not available"; return; }

        // spec_from_file_location(pluginId, path)
        PyObject *spec = PyObject_CallMethod(importlib_util, "spec_from_file_location", "ss",
                                             pluginId.UTF8String, path.UTF8String);
        if (!spec || spec == Py_None) {
            PyErr_Clear();
            Py_XDECREF(spec);
            Py_DECREF(importlib_util);
            errorMsg = [NSString stringWithFormat:@"spec_from_file_location failed for %@", path];
            return;
        }

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
        PyObject *loader = PyObject_GetAttrString(spec, "loader");
        PyObject *exec_result = loader ? PyObject_CallMethod(loader, "exec_module", "O", module) : NULL;
        Py_XDECREF(loader);

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
