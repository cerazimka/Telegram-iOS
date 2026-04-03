load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

filegroup(
    name = "EGPayWallAssets",
    srcs = glob(["Images.xcassets/**"]),
    visibility = ["//visibility:public"],
)

swift_library(
    name = "EGPayWall",
    module_name = "EGPayWall",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//ExteraGram/EGIAP:EGIAP",
        "//ExteraGram/EGLogging:EGLogging",
        "//ExteraGram/EGSimpleSettings:EGSimpleSettings",
        "//ExteraGram/EGSwiftUI:EGSwiftUI",
        "//ExteraGram/EGStrings:EGStrings",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
