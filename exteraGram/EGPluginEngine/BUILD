load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# ---------------------------------------------------------------------------
# ObjC/C bridge — Python C extension (_ios_bridge) + ObjC swizzler
#
# Python.xcframework integration:
#   1. Download Python-Apple-Support from https://github.com/beeware/Python-Apple-Support/releases
#      (target: Python-3.12-iOS-support.*.tar.gz)
#   2. Extract to third-party/Python/Python.xcframework/
#   3. Add to MODULE.bazel:
#        apple_static_xcframework_import(
#            name = "PythonFramework",
#            xcframework_imports = glob(["third-party/Python/Python.xcframework/**"]),
#            visibility = ["//visibility:public"],
#        )
#   4. Add to EGPluginEngineBridge deps:  "@PythonFramework"
#   5. Add to copts: "-I$(execpath @PythonFramework)/ios-arm64/Python.framework/Headers"
#
# Until then, EGIOSBridge.m compiles cleanly with no-op stubs via
# #if __has_include(<Python/Python.h>) guards.
# ---------------------------------------------------------------------------

objc_library(
    name = "EGPluginEngineBridge",
    srcs = [
        "Sources/ObjC/EGIOSBridge.m",
        "Sources/ObjC/EGObjCSwizzler.m",
    ],
    hdrs = [
        "Sources/ObjC/EGIOSBridge.h",
        "Sources/ObjC/EGObjCSwizzler.h",
    ],
    sdk_frameworks = [
        "Foundation",
        "UIKit",
    ],
    visibility = ["//visibility:public"],
)

# ---------------------------------------------------------------------------
# Python SDK files — shipped as app bundle data so the runtime can find them
# ---------------------------------------------------------------------------

filegroup(
    name = "PythonSDK",
    srcs = glob(["Python/SDK/**/*.py"]),
    visibility = ["//visibility:public"],
)

# ---------------------------------------------------------------------------
# Main Swift module
# ---------------------------------------------------------------------------

swift_library(
    name = "EGPluginEngine",
    module_name = "EGPluginEngine",
    srcs = glob(["Sources/Swift/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = [
        ":EGPluginEngineBridge",
        "//exteraGram/EGLogging:EGLogging",
        "//exteraGram/EGStrings:EGStrings",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/MtProtoKit:MtProtoKit",
    ],
    data = [":PythonSDK"],
    visibility = ["//visibility:public"],
)
