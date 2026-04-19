load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "EGContentAnalysis",
    module_name = "EGContentAnalysis",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
