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

@available(iOS 14.0, *)
private struct PluginRowView: View {
    @Binding var plugin: EGPlugin
    let isCompact: Bool
    let onChanged: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                pluginIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(.body)
                        .foregroundColor(.primary)
                    if !plugin.subtitle.isEmpty {
                        Text(plugin.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { plugin.isEnabled = $0; onChanged() }
                ))
                .labelsHidden()
                .disabled(plugin.isError || plugin.isNotResponding)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        plugin.isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: plugin.isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            if plugin.isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if !isCompact, !plugin.pluginDescription.isEmpty {
                        Text(plugin.pluginDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }

                    HStack(spacing: 0) {
                        actionButton(systemImage: "square.and.arrow.up", label: "Share", color: .accentColor) {
                            onShare()
                        }
                        actionButton(
                            systemImage: plugin.isPinned ? "pin.slash" : "pin",
                            label: plugin.isPinned ? "Unpin" : "Pin",
                            color: .accentColor
                        ) {
                            plugin.isPinned.toggle()
                            onChanged()
                        }
                        if plugin.hasSettings {
                            actionButton(systemImage: "gearshape", label: "Settings", color: .accentColor) {}
                        }
                        Spacer()
                        actionButton(systemImage: "trash", label: "Delete", color: .red) {
                            onDelete()
                        }
                    }
                    .padding(.top, 4)

                    if !plugin.requiresPermissions.isEmpty {
                        Text("Requires: \(plugin.requiresPermissions.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }

                    if plugin.isError {
                        Label("Plugin error", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if plugin.isNotResponding {
                        Label("Not responding", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.2), value: plugin.isExpanded)
    }

    @ViewBuilder
    private var pluginIcon: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(UIColor.secondarySystemFill))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: "puzzlepiece.extension")
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .font(.system(size: 20))
            )
    }

    @ViewBuilder
    private func actionButton(
        systemImage: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                Text(label)
                    .font(.caption2)
            }
            .foregroundColor(color)
            .frame(minWidth: 52)
            .padding(.vertical, 4)
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
                    Button(action: toggleEngine) {
                        HStack {
                            Text(i18n("Plugins.Enable", lang))
                                .foregroundColor(isSwitchingEngine ? .secondary : .primary)
                            Spacer()
                            Image(systemName: isEngineEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isEngineEnabled ? .accentColor : Color(UIColor.tertiaryLabel))
                                .font(.system(size: 22, weight: .medium))
                                .animation(.easeInOut(duration: 0.15), value: isEngineEnabled)
                        }
                        .contentShape(Rectangle())
                    }
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
                                    isCompact: PluginsController.shared.isCompactView,
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
    let buttonColor = theme.rootController.navigationBar.buttonColor

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
        image: UIImage(systemName: "magnifyingglass"),
        primaryAction: UIAction { [weak legacyController] _ in
            navState.isSearchActive = true
            legacyController?.navigationItem.rightBarButtonItems =
                [cancelButton].compactMap { $0 }
        }
    )
    searchButton?.tintColor = buttonColor

    infoButton = UIBarButtonItem(
        image: UIImage(systemName: "info.circle"),
        primaryAction: UIAction { [weak legacyController] _ in
            guard let nav = legacyController?.navigationController as? NavigationController else { return }
            nav.pushViewController(egPluginsInfoController(context: context))
        }
    )
    infoButton?.tintColor = buttonColor

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
