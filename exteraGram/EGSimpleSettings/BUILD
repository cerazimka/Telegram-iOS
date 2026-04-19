load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "EGSimpleSettings",
    module_name = "EGSimpleSettings",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//exteraGram/EGAppGroupIdentifier:EGAppGroupIdentifier",
        "//exteraGram/EGLogging:EGLogging",
    ],
    visibility = [
        "//visibility:public",
    ],
)
