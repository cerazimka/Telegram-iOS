load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "EGStrings",
    module_name = "EGStrings",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/AppBundle:AppBundle",
        "//exteraGram/EGLogging:EGLogging"
    ],
    visibility = [
        "//visibility:public",
    ],
)

filegroup(
    name = "EGLocalizableStrings",
    srcs = glob(["Strings/*.lproj/EGLocalizable.strings"]),
    visibility = [
        "//visibility:public",
    ],
)
