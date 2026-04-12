// MARK: ExteraGram

import Foundation
import SwiftUI
import LegacyUI
import EGSwiftUI
import EGStrings
import AccountContext
import Display
import AppBundle
import TelegramPresentationData

// ── Icon helpers ────────────────────────────────────────────────────────────

/// Loads a Telegram bundle image as a tintable template.
private func bundleImage(_ name: String) -> UIImage? {
    return UIImage(bundleImageName: name)?.withRenderingMode(.alwaysTemplate)
}

// Android msg_* → iOS Chat/Context Menu/* mapping:
//  msg_media       → Settings    (General / Основные)
//  msg_theme       → ApplyTheme  (Appearance / Оформление)
//  msg_discussion  → Chats       (Chats / Чаты)
//  msg_plugins     → (SF Symbol puzzlepiece — no direct match)
//  msg_fave        → Fave        (Other / Другое)
//  msg_channel     → Channels    (link: Channel)
//  msg_groups      → Groups      (link: Chat group)
//  msg_translate   → Translate   (link: Crowdin)
//  msg_language    → Browser     (link: Website)

// ── Main SwiftUI view ───────────────────────────────────────────────────────

@available(iOS 14.0, *)
private struct EGMainMenuView: View {
    @Environment(\.lang) var lang: String
    weak var wrapperController: LegacyController?
    let context: AccountContext

    var body: some View {
        List {
            // ── Header ────────────────────────────────────────────────────
            Section {
                VStack(spacing: 8) {
                    appIconImage
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text("exteraGram")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)

                    Text(versionString)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Color.clear)

            // ── Categories ────────────────────────────────────────────────
            Section {
                categoryRow(
                    bundleIcon: "Chat/Context Menu/Settings",
                    sfFallback: "slider.horizontal.3",
                    text: i18n("Settings.Menu.General", lang)
                ) {
                    push(egSettingsController(context: context))
                }
                categoryRow(
                    bundleIcon: "Chat/Context Menu/ApplyTheme",
                    sfFallback: "paintpalette",
                    text: i18n("Settings.Menu.Appearance", lang)
                ) { }
                categoryRow(
                    bundleIcon: "Chat/Context Menu/Chats",
                    sfFallback: "bubble.left",
                    text: i18n("Settings.Menu.Chats", lang)
                ) { }
                categoryRow(
                    bundleIcon: nil,
                    sfFallback: "puzzlepiece",
                    text: i18n("Settings.Menu.Plugins", lang)
                ) { }
                categoryRow(
                    bundleIcon: "Chat/Context Menu/Fave",
                    sfFallback: "star",
                    text: i18n("Settings.Menu.Other", lang)
                ) { }
            } header: {
                Text(i18n("Settings.Menu.Categories", lang))
                    .foregroundColor(.accentColor)
                    .textCase(nil)
            }

            // ── Links ─────────────────────────────────────────────────────
            Section {
                linkRow(
                    bundleIcon: "Chat/Context Menu/Channels",
                    sfFallback: "megaphone",
                    text: i18n("Settings.Menu.Channel", lang),
                    label: "@exteraGram",
                    url: "https://t.me/exteraGram"
                )
                linkRow(
                    bundleIcon: "Chat/Context Menu/Groups",
                    sfFallback: "person.2",
                    text: i18n("Settings.Menu.Chat", lang),
                    label: "@exteraChat",
                    url: "https://t.me/exteraChat"
                )
                linkRow(
                    bundleIcon: "Chat/Context Menu/Translate",
                    sfFallback: "textformat",
                    text: i18n("Settings.Menu.Translation", lang),
                    label: "Crowdin",
                    url: "https://crowdin.com/project/exteragram"
                )
                linkRow(
                    bundleIcon: "Chat/Context Menu/Browser",
                    sfFallback: "globe",
                    text: i18n("Settings.Menu.Website", lang),
                    label: "exteraGram.app",
                    url: "https://exteragram.app"
                )
            } header: {
                Text(i18n("Settings.Menu.Links", lang))
                    .foregroundColor(.accentColor)
                    .textCase(nil)
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    // ── App Icon ─────────────────────────────────────────────────────────────
    @ViewBuilder
    private var appIconImage: some View {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let lastName = iconFiles.last,
           let image = UIImage(named: lastName) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Fallback: red rounded square with paper plane
            ZStack {
                Color(UIColor(red: 0.89, green: 0.25, blue: 0.22, alpha: 1.0))
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 36))
            }
        }
    }

    // ── Row builders ─────────────────────────────────────────────────────────

    @ViewBuilder
    private func categoryRow(bundleIcon iconName: String?,
                              sfFallback: String,
                              text: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconView(bundle: iconName, sf: sfFallback)
                Text(text)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .font(.system(size: 13, weight: .semibold))
            }
        }
    }

    @ViewBuilder
    private func linkRow(bundleIcon iconName: String?,
                         sfFallback: String,
                         text: String,
                         label: String,
                         url: String) -> some View {
        Button(action: { openURL(url) }) {
            HStack(spacing: 12) {
                iconView(bundle: iconName, sf: sfFallback)
                Text(text)
                    .foregroundColor(.primary)
                Spacer()
                Text(label)
                    .foregroundColor(.accentColor)
            }
        }
    }

    /// Renders a Telegram bundle icon with SF Symbol fallback.
    @ViewBuilder
    private func iconView(bundle name: String?, sf symbol: String) -> some View {
        let image = name.flatMap { bundleImage($0) }
        if let image = image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundColor(.secondary)
        } else {
            Image(systemName: symbol)
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func push(_ controller: ViewController) {
        (wrapperController?.navigationController as? NavigationController)?
            .pushViewController(controller)
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"]             as? String ?? "?"
        return "\(version) (\(build))"
    }
}

// ── Public entry point ────────────────────────────────────────────────────────

public func egMainMenuController(context: AccountContext) -> ViewController {
    guard #available(iOS 14.0, *) else {
        // iOS 13 fallback: show the flat settings list directly.
        return egSettingsController(context: context)
    }

    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let theme   = presentationData.theme
    let strings = presentationData.strings

    let legacyController = LegacySwiftUIController(
        presentation: .navigation,
        theme: theme,
        strings: strings
    )
    legacyController.statusBar.statusBarStyle = theme.rootController.statusBarStyle.style

    let swiftUIView = EGSwiftUIView<EGMainMenuView>(legacyController: legacyController) {
        EGMainMenuView(wrapperController: legacyController, context: context)
    }
    let hostingController = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: hostingController)

    return legacyController
}
