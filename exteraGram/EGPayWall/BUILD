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
        "//exteraGram/EGIAP:EGIAP",
        "//exteraGram/EGLogging:EGLogging",
        "//exteraGram/EGSimpleSettings:EGSimpleSettings",
        "//exteraGram/EGSwiftUI:EGSwiftUI",
        "//exteraGram/EGStrings:EGStrings",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
    ],
    visibility = [
        "//visibility:public",
    ],
)
