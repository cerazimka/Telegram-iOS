load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "EGLoggingComposer",
    module_name = "EGLoggingComposer",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//exteraGram/EGLogging:EGLogging",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)