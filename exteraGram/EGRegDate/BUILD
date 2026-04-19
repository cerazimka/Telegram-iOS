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
        "//exteraGram/EGRegDateScheme:EGRegDateScheme",
        "//exteraGram/EGSimpleSettings:EGSimpleSettings",
        "//exteraGram/EGAPI:EGAPI",
        "//exteraGram/EGAPIToken:EGAPIToken",
        "//exteraGram/EGDeviceToken:EGDeviceToken",
        "//exteraGram/EGStrings:EGStrings",

        "//submodules/AccountContext:AccountContext",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
    ],
    visibility = [
        "//visibility:public",
    ],
)