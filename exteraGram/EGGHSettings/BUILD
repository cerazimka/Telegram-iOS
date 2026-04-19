load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "EGGHSettings",
    module_name = "EGGHSettings",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//exteraGram/EGGHSettingsScheme:EGGHSettingsScheme",
        "//exteraGram/EGLogging:EGLogging",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)