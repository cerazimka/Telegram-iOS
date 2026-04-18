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

// MARK: - Share Sheet

@available(iOS 14.0, *)
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Install Plugin Sheet

@available(iOS 14.0, *)
private struct InstallPluginSheet: View {
    let lang: String
    let onInstall: (EGPlugin) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.accentColor)

                Text(i18n("Plugins.Install.Title", lang))
                    .font(.title2.bold())

                Text(i18n("Plugins.Install.Description", lang))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                if isLoading {
                    ProgressView()
                        .padding(.bottom, 32)
                } else {
                    VStack(spacing: 12) {
                        Button(action: performInstall) {
                            Text(i18n("Plugins.Install.Confirm", lang))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)

                        Button(i18n("Plugins.Cancel", lang)) {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing:
                Button(i18n("Plugins.Cancel", lang)) {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }

    private func performInstall() {
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let stub = EGPlugin(
                name: "Example Plugin",
                subtitle: "ExteraGram",
                pluginDescription: "A sample plugin for demonstration purposes.",
                version: "1.0"
            )
            onInstall(stub)
            isLoading = false
            presentationMode.wrappedValue.dismiss()
        }
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

    @State private var isEngineEnabled: Bool = PluginsController.shared.isEngineEnabled
    @State private var plugins: [EGPlugin] = PluginsController.shared.plugins
    @State private var searchText: String = ""
    @State private var showingInstallSheet: Bool = false
    @State private var pluginToShare: EGPlugin? = nil
    @State private var pluginToDelete: String? = nil
    @State private var showDeleteAlert: Bool = false

    private var displayPlugins: [EGPlugin] {
        let base: [EGPlugin]
        if searchText.isEmpty {
            base = plugins
        } else {
            base = plugins.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.subtitle.localizedCaseInsensitiveContains(searchText)
            }
        }
        return base.sorted { $0.isPinned && !$1.isPinned }
    }

    var body: some View {
        List {
            Section {
                Toggle(i18n("Plugins.Enable", lang), isOn: Binding(
                    get: { isEngineEnabled },
                    set: { v in
                        isEngineEnabled = v
                        PluginsController.shared.isEngineEnabled = v
                    }
                ))
            }

            if isEngineEnabled {
                if !plugins.isEmpty {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField(i18n("Plugins.Search", lang), text: $searchText)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(Color(UIColor.tertiaryLabel))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section {
                    if displayPlugins.isEmpty {
                        Text(searchText.isEmpty
                            ? i18n("Plugins.Empty", lang)
                            : i18n("Plugins.NoResults", lang))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
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
                } header: {
                    if !plugins.isEmpty {
                        Text(i18n("Plugins.Installed", lang).uppercased())
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }

                Section {
                    Button(action: { showingInstallSheet = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                            Text(i18n("Plugins.Install", lang))
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .sheet(isPresented: $showingInstallSheet) {
            InstallPluginSheet(lang: lang) { plugin in
                plugins.append(plugin)
                PluginsController.shared.plugins = plugins
            }
        }
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

    legacyController.navigationItem.rightBarButtonItem = UIBarButtonItem(
        image: UIImage(systemName: "info.circle"),
        primaryAction: UIAction { [weak legacyController] _ in
            guard let nav = legacyController?.navigationController as? NavigationController else { return }
            nav.pushViewController(egPluginsInfoController(context: context))
        }
    )

    let swiftUIView = EGSwiftUIView<EGPluginsView>(legacyController: legacyController) {
        EGPluginsView(wrapperController: legacyController, context: context)
    }
    let hostingController = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: hostingController)

    return legacyController
}
