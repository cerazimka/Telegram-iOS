load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "EGRegDate",
    module_name = "EGRegDate",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//ExteraGram/EGRegDateScheme:EGRegDateScheme",
        "//ExteraGram/EGSimpleSettings:EGSimpleSettings",
        "//ExteraGram/EGAPI:EGAPI",
        "//ExteraGram/EGAPIToken:EGAPIToken",
        "//ExteraGram/EGDeviceToken:EGDeviceToken",
        "//ExteraGram/EGStrings:EGStrings",

        "//submodules/AccountContext:AccountContext",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
    ],
    visibility = [
        "//visibility:public",
    ],
)