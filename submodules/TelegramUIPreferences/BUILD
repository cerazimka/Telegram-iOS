load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

egsrcs = [
    "//exteraGram/EGStatus:EGStatus"
]

swift_library(
    name = "TelegramUIPreferences",
    module_name = "TelegramUIPreferences",
    srcs = egsrcs + glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Postbox:Postbox",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
