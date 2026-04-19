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
        "//exteraGram/EGLogging:EGLogging",
        "//exteraGram/EGWebAppExtensions:EGWebAppExtensions",
        "//exteraGram/EGSimpleSettings:EGSimpleSettings",
        "//exteraGram/EGWebSettingsScheme:EGWebSettingsScheme",
        "//exteraGram/EGRegDateScheme:EGRegDateScheme",
        "//exteraGram/EGRequests:EGRequests",
        "//exteraGram/EGConfig:EGConfig",
        "//exteraGram/EGBadges:EGBadges",
    ],
    visibility = [
        "//visibility:public",
    ],
)
