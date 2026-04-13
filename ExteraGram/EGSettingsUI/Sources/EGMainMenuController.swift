// MARK: ExteraGram

import Foundation
import SwiftUI
import LegacyUI
import EGSwiftUI
import EGStrings
import AccountContext
import AppBundle
import Display
import TelegramPresentationData

// ── SF Symbol mapping (confirmed from Android APK reverse engineering)
//
//  msg_media       → square.grid.2x2   (Основные)
//  msg_theme       → paintpalette      (Оформление)
//  msg_discussion  → bubble.left       (Чаты)
//  msg_plugins     → puzzlepiece       (Плагины)
//  msg_fave        → star              (Другое)
//  msg_channel     → megaphone         (Канал)
//  msg_groups      → person.2          (Чаты — ссылки)
//  msg_translate   → translate (iOS 15+) / Chat/Context Menu/Translate (iOS 14)
//  msg_language    → globe             (Веб-сайт)

@available(iOS 14.0, *)
private struct EGMainMenuView: View {
    @Environment(\.lang) var lang: String
    @Environment(\.navigationBarHeight) var navigationBarHeight: CGFloat
    weak var wrapperController: LegacyController?
    let context: AccountContext

    // `translate` SF Symbol requires iOS 15+; use bundle icon on iOS 14.
    private var translateIcon: AnyView {
        if #available(iOS 15.0, *) {
            return AnyView(
                Image(systemName: "translate")
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
            )
        }
        if let img = UIImage(bundleImageName: "Chat/Context Menu/Translate")?
            .withRenderingMode(.alwaysTemplate) {
            return AnyView(
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundColor(.secondary)
            )
        }
        return AnyView(
            Image(systemName: "textformat")
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
        )
    }

    var body: some View {
        List {
            // ── Header (HeaderSettingsCell analog) ───────────────────────
            Section {
                VStack(spacing: 8) {
                    appIconImage
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        // Long press → toggle icon shape + haptic (mirrors Android behavior)
                        .onLongPressGesture {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }

                    // 20sp bold, R.string.exteraAppName
                    Text("exteraGram")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)

                    // BUILD_VERSION_STRING + " (" + versionCode + ")", 15sp gray
                    Text(versionString)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, navigationBarHeight + 20)
                .padding(.bottom, 20)
                .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Color.clear)

            // ── Категории ────────────────────────────────────────────────
            Section {
                categoryRow(systemImage: "square.grid.2x2",
                            text: i18n("Settings.Menu.General", lang)) {
                    push(egSettingsController(context: context))
                }
                categoryRow(systemImage: "paintpalette",
                            text: i18n("Settings.Menu.Appearance", lang)) { }
                categoryRow(systemImage: "bubble.left",
                            text: i18n("Settings.Menu.Chats", lang)) { }
                categoryRow(systemImage: "puzzlepiece",
                            text: i18n("Settings.Menu.Plugins", lang)) { }
                categoryRow(systemImage: "star",
                            text: i18n("Settings.Menu.Other", lang)) { }
            } header: {
                sectionHeader(i18n("Settings.Menu.Categories", lang))
            }

            // ── Ссылки ────────────────────────────────────────────────────
            Section {
                linkRow(icon: AnyView(sfIcon("megaphone")),
                        text: i18n("Settings.Menu.Channel", lang),
                        label: "@exteraGram",
                        url: "https://t.me/exteraGram")
                linkRow(icon: AnyView(sfIcon("person.2")),
                        text: i18n("Settings.Menu.Chat", lang),
                        label: "@exteraChat",
                        url: "https://t.me/exteraChat")
                linkRow(icon: translateIcon,
                        text: i18n("Settings.Menu.Translation", lang),
                        label: "Crowdin",
                        url: "https://crowdin.com/project/exteralocales")
                linkRow(icon: AnyView(sfIcon("globe")),
                        text: i18n("Settings.Menu.Website", lang),
                        label: "exteraGram.app",
                        url: "https://exteraGram.app")
            } header: {
                sectionHeader(i18n("Settings.Menu.Links", lang))
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    // ── App Icon ─────────────────────────────────────────────────────────────
    // Uses EGDefault from the asset catalog; falls back to bundle icon → red square
    @ViewBuilder
    private var appIconImage: some View {
        if let image = UIImage(bundleImageName: "EGDefault") {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
                  let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
                  let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
                  let lastName = iconFiles.last,
                  let image = UIImage(named: lastName) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
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
    private func categoryRow(systemImage: String,
                              text: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                sfIcon(systemImage)
                Text(text)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func linkRow(icon: AnyView,
                         text: String,
                         label: String,
                         url: String) -> some View {
        Button(action: { openURL(url) }) {
            HStack(spacing: 12) {
                icon
                Text(text)
                    .foregroundColor(.primary)
                Spacer()
                Text(label)
                    .foregroundColor(.accentColor)
            }
        }
        .buttonStyle(.plain)
    }

    private func sfIcon(_ name: String) -> some View {
        Image(systemName: name)
            .foregroundColor(.secondary)
            .frame(width: 22, height: 22)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // Matches Telegram's ItemListSectionHeaderItem: 13pt regular, secondaryLabel color, UPPERCASE
    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(Color(UIColor.secondaryLabel))
    }

    private func push(_ controller: ViewController) {
        (wrapperController?.navigationController as? NavigationController)?
            .pushViewController(controller)
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    // "12.5.1 (65819)" — mirrors Android BUILD_VERSION_STRING + " (" + versionCode + ")"
    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"]             as? String ?? "?"
        return "\(version) (\(build))"
    }
}

// ── Public entry point ────────────────────────────────────────────────────────

public func egMainMenuController(context: AccountContext) -> ViewController {
    guard #available(iOS 14.0, *) else {
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
