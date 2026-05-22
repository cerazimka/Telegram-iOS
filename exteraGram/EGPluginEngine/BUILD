load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

# ---------------------------------------------------------------------------
# ObjC/C bridge — Python C extension (_ios_bridge) + ObjC swizzler
#
# Python.xcframework is provided by @python_apple_support (see MODULE.bazel).
# Bazel downloads Python-3.14-iOS-support.b9.tar.gz automatically at build time.
#
# EGIOSBridge.m uses #if __has_include(<Python/Python.h>) so it compiles
# cleanly even if the xcframework is not yet fetched.
# ---------------------------------------------------------------------------

objc_library(
    name = "EGPluginEngineBridge",
    enable_modules = True,
    module_name = "EGPluginEngineBridge",
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
    deps = [
        "@python_apple_support//:Python",
        "//third-party/ZipArchive:ZipArchive",
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

# Sample plugins shipped with the app (available in Settings → Plugins → Browse)
filegroup(
    name = "SamplePlugins",
    srcs = glob(["Python/Plugins/**/*.plugin"]),
    visibility = ["//visibility:public"],
)

# Pure-Python third-party packages, shipped as a single zip so the bundler
# doesn't try to flatten multiple package __init__.py files into the
# framework root (which would collide). EGPluginRuntime extracts it to a
# cache directory on first launch and appends that directory to sys.path.
filegroup(
    name = "BundledSitePackages",
    srcs = ["Python/site-packages/bundled-site-packages.zip"],
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
    data = [
        ":PythonSDK",
        ":BundledSitePackages",
    ],
    visibility = ["//visibility:public"],
)
