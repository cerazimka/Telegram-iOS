// MARK: ExteraGram

import Foundation
import SwiftUI
import LegacyUI
import EGSwiftUI
import EGStrings
import AccountContext
import Display
import TelegramPresentationData

// MARK: - Data Model

public struct EGPlugin: Identifiable, Codable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var pluginDescription: String
    public var version: String
    public var iconUrl: String?
    public var isEnabled: Bool
    public var isPinned: Bool
    public var hasSettings: Bool
    public var requiresPermissions: [String]

    public var isExpanded: Bool = false
    public var isError: Bool = false
    public var isNotResponding: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, name, subtitle, version, iconUrl
        case pluginDescription = "description"
        case isEnabled, isPinned, hasSettings, requiresPermissions
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        subtitle: String = "",
        pluginDescription: String = "",
        version: String = "1.0",
        iconUrl: String? = nil,
        isEnabled: Bool = true,
        isPinned: Bool = false,
        hasSettings: Bool = false,
        requiresPermissions: [String] = []
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.pluginDescription = pluginDescription
        self.version = version
        self.iconUrl = iconUrl
        self.isEnabled = isEnabled
        self.isPinned = isPinned
        self.hasSettings = hasSettings
        self.requiresPermissions = requiresPermissions
    }
}

// MARK: - Engine Stub

public final class PluginsController {
    public static let shared = PluginsController()
    private init() {}

    public var plugins: [EGPlugin] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "eg_plugins_v1"),
                  let list = try? JSONDecoder().decode([EGPlugin].self, from: data)
            else { return [] }
            return list
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "eg_plugins_v1")
        }
    }

    public var isEngineEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "eg_engine_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "eg_engine_enabled") }
    }

    public var isDevMode: Bool {
        get { UserDefaults.standard.bool(forKey: "eg_plugins_dev_mode") }
        set { UserDefaults.standard.set(newValue, forKey: "eg_plugins_dev_mode") }
    }

    public var isCompactView: Bool {
        get { UserDefaults.standard.bool(forKey: "eg_plugins_compact") }
        set { UserDefaults.standard.set(newValue, forKey: "eg_plugins_compact") }
    }

    public var isSafeModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "eg_plugins_safe_mode") }
        set { UserDefaults.standard.set(newValue, forKey: "eg_plugins_safe_mode") }
    }
}

// MARK: - Search/Nav State Bridge
// Bridges UIKit nav bar buttons with the SwiftUI list state.

@available(iOS 14.0, *)
private final class PluginsNavState: ObservableObject {
    @Published var isSearchActive: Bool = false
    @Published var searchText: String = ""
    var onSearchDeactivated: (() -> Void)?

    func deactivate() {
        isSearchActive = false
        searchText = ""
        onSearchDeactivated?()
    }
}

// MARK: - Share Sheet

@available(iOS 14.0, *)
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Empty State View
// Mirrors Android EmptyPluginsView: emoji sticker + descriptive text.
// isSearching=true  → 🔎 + PluginsNotFound
// isSearching=false → 📂 + PluginsInfo (no plugins installed)

@available(iOS 14.0, *)
private struct PluginsEmptyView: View {
    let isSearching: Bool
    let lang: String

    var body: some View {
        VStack(spacing: 16) {
            Text(isSearching ? "🔎" : "📂")
                .font(.system(size: 52))
            Text(i18n(isSearching ? "Plugins.NoResults" : "Plugins.Empty", lang))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Plugin Row
// Layout matches the screenshot exactly:
// HStack: [optional icon 52pt] [VStack: name bold / subtitle] [Spacer] [Toggle]
// Below: description text, divider, action buttons (bundle icons, no labels).

@available(iOS 14.0, *)
private struct PluginRowView: View {
    @Binding var plugin: EGPlugin
    let lang: String
    let onChanged: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    // "v{version} · {author}"
    private var subtitleString: String {
        let ver = "v\(plugin.version)"
        return plugin.subtitle.isEmpty ? ver : "\(ver) · \(plugin.subtitle)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header row: icon (if any) + name/subtitle + toggle ──────────
            HStack(alignment: .center, spacing: 12) {
                if plugin.iconUrl != nil {
                    iconView(size: 52)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(subtitleString)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if !plugin.isError && !plugin.isNotResponding {
                    Toggle("", isOn: Binding(
                        get: { plugin.isEnabled },
                        set: { plugin.isEnabled = $0; onChanged() }
                    ))
                    .labelsHidden()
                    .fixedSize()
                }
            }

            // ── Description / error / notResponding ──────────────────────────
            descriptionSection

            // ── Requirements ─────────────────────────────────────────────────
            if !plugin.requiresPermissions.isEmpty {
                Text(plugin.requiresPermissions.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .padding(.top, 6)
            }

            // ── Divider ───────────────────────────────────────────────────────
            Divider()
                .padding(.top, 10)

            // ── Action buttons ────────────────────────────────────────────────
            HStack(spacing: 0) {
                cellButton(image: "msg_share") { onShare() }
                cellButton(image: "msg_openin") {} // stub: real engine needed
                cellButton(image: plugin.isPinned ? "msg_unpin" : "msg_pin") {
                    plugin.isPinned.toggle()
                    onChanged()
                }
                if plugin.hasSettings && plugin.isEnabled && !plugin.isError && !plugin.isNotResponding {
                    cellButton(image: "msg_settings") {}
                }
                Spacer()
                cellButton(
                    image: plugin.isNotResponding ? "ic_ab_other" : "msg_delete",
                    isDestructive: !plugin.isNotResponding
                ) {
                    if !plugin.isNotResponding { onDelete() }
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
        .padding(.top, 10)
    }

    @ViewBuilder private var descriptionSection: some View {
        if plugin.isNotResponding {
            Text(i18n("Plugins.State.NotResponding", lang))
                .font(.subheadline)
                .foregroundColor(.red)
                .padding(.top, 6)
        } else if plugin.isError {
            Text(i18n("Plugins.State.Error", lang))
                .font(.subheadline)
                .foregroundColor(.red)
                .padding(.top, 6)
        } else if !plugin.pluginDescription.isEmpty {
            Text(plugin.pluginDescription)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func iconView(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Color(UIColor.secondarySystemFill))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "puzzlepiece.extension")
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .font(.system(size: size * 0.4))
            )
    }

    @ViewBuilder
    private func cellButton(
        image: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(image)
                .renderingMode(.template)
                .foregroundColor(isDestructive ? .red : Color(UIColor.secondaryLabel))
                .frame(width: 44, height: 40)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main Plugins View

@available(iOS 14.0, *)
private struct EGPluginsView: View {
    @Environment(\.lang) var lang: String
    weak var wrapperController: LegacyController?
    let context: AccountContext
    @ObservedObject var navState: PluginsNavState

    @State private var isEngineEnabled: Bool = PluginsController.shared.isEngineEnabled
    @State private var plugins: [EGPlugin] = PluginsController.shared.plugins
    @State private var isSwitchingEngine: Bool = false
    @State private var pluginToShare: EGPlugin? = nil
    @State private var pluginToDelete: String? = nil
    @State private var showDeleteAlert: Bool = false

    // Mirrors fillItems ordering: pinned (alphabetical) first, then non-pinned (alphabetical).
    // When searching, filters by name only (mirrors lambda$fillItems$1).
    private var displayPlugins: [EGPlugin] {
        var pool = plugins
        if !navState.searchText.isEmpty {
            pool = pool.filter { $0.name.lowercased().contains(navState.searchText.lowercased()) }
        }
        let pinned   = pool.filter {  $0.isPinned }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        let unpinned = pool.filter { !$0.isPinned }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        return pinned + unpinned
    }

    private var showEmptyState: Bool {
        guard isEngineEnabled else { return false }
        if !navState.searchText.isEmpty { return displayPlugins.isEmpty }
        return plugins.isEmpty
    }

    var body: some View {
        List {
            // Engine toggle — hidden while search is active (mirrors fillItems: only added when !searching)
            if !navState.isSearchActive {
                Section {
                    Toggle(i18n("Plugins.Enable", lang), isOn: Binding(
                        get: { isEngineEnabled },
                        set: { _ in toggleEngine() }
                    ))
                    .disabled(isSwitchingEngine)
                }
            }

            // Plugin list — only when engine is enabled
            if isEngineEnabled {
                Section {
                    // Inline search field (shown when search is active from nav bar)
                    if navState.isSearchActive {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField(i18n("Plugins.Search", lang), text: $navState.searchText)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            if !navState.searchText.isEmpty {
                                Button(action: { navState.searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(Color(UIColor.tertiaryLabel))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if showEmptyState {
                        PluginsEmptyView(
                            isSearching: !navState.searchText.isEmpty,
                            lang: lang
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } else {
                        ForEach(displayPlugins) { plugin in
                            if let idx = plugins.firstIndex(where: { $0.id == plugin.id }) {
                                PluginRowView(
                                    plugin: $plugins[idx],
                                    lang: lang,
                                    onChanged: { PluginsController.shared.plugins = plugins },
                                    onShare: { pluginToShare = plugins[idx] },
                                    onDelete: {
                                        pluginToDelete = plugins[idx].id
                                        showDeleteAlert = true
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .sheet(item: $pluginToShare) { plugin in
            ActivityView(items: [plugin.name])
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text(i18n("Plugins.Delete.Title", lang)),
                message: Text(i18n("Plugins.Delete.Message", lang)),
                primaryButton: .destructive(Text(i18n("Plugins.Delete.Confirm", lang))) {
                    if let id = pluginToDelete {
                        plugins.removeAll { $0.id == id }
                        PluginsController.shared.plugins = plugins
                        pluginToDelete = nil
                    }
                },
                secondaryButton: .cancel(Text(i18n("Plugins.Cancel", lang))) {
                    pluginToDelete = nil
                }
            )
        }
    }

    // Mirrors togglePluginsEngine: guarded by isSwitchingEngineState,
    // collapses search when engine is disabled.
    private func toggleEngine() {
        guard !isSwitchingEngine else { return }
        isSwitchingEngine = true
        let enabling = !isEngineEnabled
        withAnimation(.easeInOut(duration: 0.15)) {
            isEngineEnabled = enabling
        }
        PluginsController.shared.isEngineEnabled = enabling
        if !enabling, navState.isSearchActive {
            navState.deactivate()
        }
        // Stub: real engine calls PluginsController.init(runnable) / shutdown(runnable);
        // the runnable clears isSwitchingEngineState after async work completes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isSwitchingEngine = false
        }
    }
}

// MARK: - Public Entry Point

public func egPluginsController(context: AccountContext) -> ViewController {
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
    legacyController.title = i18n("Settings.Menu.Plugins", strings.baseLanguageCode)
    legacyController.statusBar.statusBarStyle = theme.rootController.statusBarStyle.style

    let navState = PluginsNavState()
    let buttonColor = theme.rootController.navigationBar.accentTextColor

    // Mirrors Android: searchItem + infoItem both in the action bar.
    // When search expands → infoItem hidden (visibility GONE). When collapsed → restored.
    var infoButton: UIBarButtonItem? = nil
    var searchButton: UIBarButtonItem? = nil
    var cancelButton: UIBarButtonItem? = nil

    cancelButton = UIBarButtonItem(
        title: i18n("Plugins.Cancel", strings.baseLanguageCode),
        primaryAction: UIAction { [weak legacyController] _ in
            navState.deactivate()
            legacyController?.navigationItem.rightBarButtonItems =
                [infoButton, searchButton].compactMap { $0 }
        }
    )
    cancelButton?.tintColor = buttonColor

    searchButton = UIBarButtonItem(
        image: PresentationResourcesRootController.navigationSearchIcon(theme),
        primaryAction: UIAction { [weak legacyController] _ in
            navState.isSearchActive = true
            legacyController?.navigationItem.rightBarButtonItems =
                [cancelButton].compactMap { $0 }
        }
    )

    infoButton = UIBarButtonItem(
        image: PresentationResourcesRootController.navigationInfoIcon(theme),
        primaryAction: UIAction { [weak legacyController] _ in
            guard let nav = legacyController?.navigationController as? NavigationController else { return }
            nav.pushViewController(egPluginsInfoController(context: context))
        }
    )

    // Restore both buttons when search collapses from the SwiftUI side.
    navState.onSearchDeactivated = { [weak legacyController] in
        legacyController?.navigationItem.rightBarButtonItems =
            [infoButton, searchButton].compactMap { $0 }
    }

    legacyController.navigationItem.rightBarButtonItems =
        [infoButton, searchButton].compactMap { $0 }

    let swiftUIView = EGSwiftUIView<EGPluginsView>(legacyController: legacyController, manageSafeArea: true) {
        EGPluginsView(wrapperController: legacyController, context: context, navState: navState)
    }
    let hostingController = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: hostingController)

    return legacyController
}
