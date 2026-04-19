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
        "//exteraGram/EGAPI:EGAPI",
        "//exteraGram/EGAPIToken:EGAPIToken",
        "//exteraGram/EGLogging:EGLogging",
        "//exteraGram/EGSimpleSettings:EGSimpleSettings",
        "//exteraGram/EGBadges:EGBadges",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramCore:TelegramCore",
    ],
    visibility = [
        "//visibility:public",
    ],
)
