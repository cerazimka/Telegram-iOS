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

@available(iOS 14.0, *)
private struct EGMainMenuView: View {
    @Environment(\.lang) var lang: String
    @Environment(\.navigationBarHeight) var navigationBarHeight: CGFloat
    weak var wrapperController: LegacyController?
    let context: AccountContext

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
                .padding(.top, navigationBarHeight)
                .padding(.bottom, 20)
                .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Color.clear)

            // ── Категории ────────────────────────────────────────────────
            Section {
                categoryRow(bundleImageName: "msg_media",
                            text: i18n("Settings.Menu.General", lang)) {
                    push(egSettingsController(context: context))
                }
                categoryRow(bundleImageName: "msg_theme",
                            text: i18n("Settings.Menu.Appearance", lang)) { }
                categoryRow(bundleImageName: "msg_discussion",
                            text: i18n("Settings.Menu.Chats", lang)) { }
                categoryRow(bundleImageName: "msg_plugins",
                            text: i18n("Settings.Menu.Plugins", lang)) {
                    push(egPluginsController(context: context))
                }
                categoryRow(bundleImageName: "msg_fave",
                            text: i18n("Settings.Menu.Other", lang)) { }
            } header: {
                sectionHeader(i18n("Settings.Menu.Categories", lang))
            }

            // ── Ссылки ────────────────────────────────────────────────────
            Section {
                linkRow(icon: AnyView(telegramIcon("msg_channel")),
                        text: i18n("Settings.Menu.Channel", lang),
                        label: "@exteraGram",
                        url: "https://t.me/exteraGram")
                linkRow(icon: AnyView(telegramIcon("msg_groups")),
                        text: i18n("Settings.Menu.Chat", lang),
                        label: "@exteraChat",
                        url: "https://t.me/exteraChat")
                linkRow(icon: AnyView(telegramIcon("msg_translate")),
                        text: i18n("Settings.Menu.Translation", lang),
                        label: "Crowdin",
                        url: "https://crowdin.com/project/exteralocales")
                linkRow(icon: AnyView(telegramIcon("msg_language")),
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
    private func categoryRow(bundleImageName: String,
                              text: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                telegramIcon(bundleImageName)
                Text(text)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .font(.system(size: 13, weight: .semibold))
            }
            .contentShape(Rectangle())
        }
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
            .contentShape(Rectangle())
        }
    }

    // Renders a 29×29 icon: red rounded-rect background + white-tinted symbol.
    // Source PNGs are 24px declared @3x (= 8pt natural size). Drawing at a fixed
    // 17pt keeps the icon proportional regardless of the image's declared scale.
    private func telegramIcon(_ bundleImageName: String) -> some View {
        let size = CGSize(width: 29, height: 29)
        let iconPt: CGFloat = 17
        let renderer = UIGraphicsImageRenderer(size: size)
        let result = renderer.image { _ in
            UIColor.systemRed.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 7).fill()

            if let tinted = generateTintedImage(image: UIImage(bundleImageName: bundleImageName),
                                                color: .white) {
                let x = (size.width - iconPt) / 2
                let y = (size.height - iconPt) / 2
                tinted.draw(in: CGRect(x: x, y: y, width: iconPt, height: iconPt))
            }
        }
        return Image(uiImage: result).frame(width: 29, height: 29)
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
