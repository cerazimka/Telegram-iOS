load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "EGAPIToken",
    module_name = "EGAPIToken",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramCore:TelegramCore",
        "//ExteraGram/EGLogging:EGLogging",
        "//ExteraGram/EGWebSettingsScheme:EGWebSettingsScheme",
        "//ExteraGram/EGConfig:EGConfig",
        "//ExteraGram/EGWebAppExtensions:EGWebAppExtensions",
    ],
    visibility = [
        "//visibility:public",
    ],
)
