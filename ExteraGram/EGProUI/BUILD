load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")


swift_library(
    name = "EGProUI",
    module_name = "EGProUI",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//ExteraGram/EGKeychainBackupManager:EGKeychainBackupManager",
        "//ExteraGram/EGItemListUI:EGItemListUI",
        "//ExteraGram/EGLogging:EGLogging",
        "//ExteraGram/EGSimpleSettings:EGSimpleSettings",
        "//ExteraGram/EGStrings:EGStrings",
        "//ExteraGram/EGAPI:EGAPI",
        "//ExteraGram/EGAPIToken:EGAPIToken",
        "//ExteraGram/EGSwiftUI:EGSwiftUI",
        #
        "//submodules/SettingsUI:SettingsUI",
        #
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Display:Display",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/OverlayStatusController:OverlayStatusController",
        "//submodules/AccountContext:AccountContext",
        "//submodules/AppBundle:AppBundle",
        "//submodules/TelegramUI/Components/Settings/PeerNameColorScreen",
        "//submodules/UndoUI:UndoUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)
