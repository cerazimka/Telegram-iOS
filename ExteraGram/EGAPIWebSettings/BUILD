load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "EGAPIWebSettings",
    module_name = "EGAPIWebSettings",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//ExteraGram/EGAPI:EGAPI",
        "//ExteraGram/EGAPIToken:EGAPIToken",
        "//ExteraGram/EGLogging:EGLogging",
        "//ExteraGram/EGSimpleSettings:EGSimpleSettings",
        "//ExteraGram/EGBadges:EGBadges",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
