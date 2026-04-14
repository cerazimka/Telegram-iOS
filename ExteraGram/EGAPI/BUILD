load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "EGAPI",
    module_name = "EGAPI",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//ExteraGram/EGLogging:EGLogging",
        "//ExteraGram/EGWebAppExtensions:EGWebAppExtensions",
        "//ExteraGram/EGSimpleSettings:EGSimpleSettings",
        "//ExteraGram/EGWebSettingsScheme:EGWebSettingsScheme",
        "//ExteraGram/EGRegDateScheme:EGRegDateScheme",
        "//ExteraGram/EGRequests:EGRequests",
        "//ExteraGram/EGConfig:EGConfig",
        "//ExteraGram/EGBadges:EGBadges",
    ],
    visibility = [
        "//visibility:public",
    ],
)
