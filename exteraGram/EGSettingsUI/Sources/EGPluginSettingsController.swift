// MARK: exteraGram — per-plugin settings screen
//
// Renders the SettingItem list returned by `_eg_internal.get_settings_items`
// (Python SDK). Each setting type maps to a SwiftUI control:
//
//   header   → Section header
//   switch   → Toggle (persisted under "eg.plugin.<id>.<key>")
//   selector → Picker (segmented or wheel depending on item count)
//   input    → TextField
//   slider   → Slider with min/max
//   text     → Button (calls on_click)
//   divider  → footer caption under the previous section

import Foundation
import SwiftUI
import LegacyUI
import EGSwiftUI
import EGStrings
import EGPluginEngine
import AccountContext
import Display
import TelegramPresentationData

@available(iOS 14.0, *)
private final class PluginSettingsViewModel: ObservableObject {
    let pluginId: String
    @Published var items: [[String: Any]] = []

    init(pluginId: String) {
        self.pluginId = pluginId
    }

    func reload() {
        items = PluginsController.shared.getPluginSettingsItems(pluginId)
    }

    // MARK: - Value access (persisted UserDefaults bucket)

    func value(forKey key: String, fallback def: Any?) -> Any? {
        guard !key.isEmpty else { return def }
        return PluginsController.shared.getSetting(pluginId, key: key, default: def)
    }

    func setValue(_ value: Any, forKey key: String, atIndex index: Int) {
        if !key.isEmpty {
            PluginsController.shared.setSetting(pluginId, key: key, value: value)
        }
        PluginsController.shared.notifyPluginSettingChange(pluginId, index: index, value: value)
    }

    func click(atIndex index: Int) {
        PluginsController.shared.notifyPluginSettingClick(pluginId, index: index)
    }
}

@available(iOS 14.0, *)
private struct PluginSettingsView: View {
    @ObservedObject var viewModel: PluginSettingsViewModel
    let lang: String

    var body: some View {
        List {
            ForEach(Array(viewModel.items.enumerated()), id: \.offset) { idx, item in
                rowView(for: item, at: idx)
            }
        }
        .listStyle(InsetGroupedListStyle())
        .onAppear { viewModel.reload() }
    }

    @ViewBuilder
    private func rowView(for item: [String: Any], at index: Int) -> some View {
        let type = (item["type"] as? String) ?? "text"
        switch type {
        case "header":   headerRow(item)
        case "switch", "toggle": switchRow(item, at: index)
        case "selector": selectorRow(item, at: index)
        case "input":    inputRow(item, at: index)
        case "slider":   sliderRow(item, at: index)
        case "text":     textRow(item, at: index)
        case "divider":  dividerRow(item)
        default:         EmptyView()
        }
    }

    // MARK: - Row builders

    private func headerRow(_ item: [String: Any]) -> some View {
        Text((item["title"] as? String ?? "").uppercased())
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(Color(UIColor.secondaryLabel))
            .padding(.top, 8)
    }

    private func dividerRow(_ item: [String: Any]) -> some View {
        let text = item["title"] as? String ?? ""
        return Text(text)
            .font(.system(size: 13))
            .foregroundColor(Color(UIColor.secondaryLabel))
            .padding(.vertical, 4)
    }

    private func switchRow(_ item: [String: Any], at index: Int) -> some View {
        let key = item["key"] as? String ?? ""
        let title = item["title"] as? String ?? ""
        let subtitle = item["subtitle"] as? String ?? ""
        let defaultValue = item["default"] as? Bool ?? false
        let current = (viewModel.value(forKey: key, fallback: defaultValue) as? Bool) ?? defaultValue

        return HStack(alignment: .center, spacing: 12) {
            iconView(item)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { current },
                set: { v in viewModel.setValue(v, forKey: key, atIndex: index) }
            ))
            .labelsHidden()
        }
    }

    private func selectorRow(_ item: [String: Any], at index: Int) -> some View {
        let key = item["key"] as? String ?? ""
        let title = item["title"] as? String ?? ""
        let optionsAny = item["options"] as? [Any] ?? []
        let options = optionsAny.map { String(describing: $0) }
        let defaultIdx = item["default"] as? Int ?? 0
        let current = (viewModel.value(forKey: key, fallback: defaultIdx) as? Int) ?? defaultIdx
        let clamped = max(0, min(current, max(0, options.count - 1)))

        return Picker(selection: Binding(
            get: { clamped },
            set: { v in viewModel.setValue(v, forKey: key, atIndex: index) }
        ), label: HStack {
            iconView(item)
            Text(title)
        }) {
            ForEach(0..<options.count, id: \.self) { i in
                Text(options[i]).tag(i)
            }
        }
    }

    private func inputRow(_ item: [String: Any], at index: Int) -> some View {
        let key = item["key"] as? String ?? ""
        let title = item["title"] as? String ?? ""
        let defaultValue = item["default"] as? String ?? ""
        let current = (viewModel.value(forKey: key, fallback: defaultValue) as? String) ?? defaultValue

        return HStack {
            iconView(item)
            Text(title)
            Spacer()
            TextField("", text: Binding(
                get: { current },
                set: { v in viewModel.setValue(v, forKey: key, atIndex: index) }
            ))
            .multilineTextAlignment(.trailing)
            .foregroundColor(.secondary)
        }
    }

    private func sliderRow(_ item: [String: Any], at index: Int) -> some View {
        let key = item["key"] as? String ?? ""
        let title = item["title"] as? String ?? ""
        let minV = (item["min_value"] as? Double) ?? 0
        let maxV = (item["max_value"] as? Double) ?? 100
        let defaultValue = (item["default"] as? Double) ?? minV
        let raw = viewModel.value(forKey: key, fallback: defaultValue) as? Double ?? defaultValue

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                iconView(item)
                Text(title)
                Spacer()
                Text(String(format: "%.0f", raw))
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            Slider(value: Binding(
                get: { raw },
                set: { v in viewModel.setValue(v, forKey: key, atIndex: index) }
            ), in: minV...max(maxV, minV + 0.001))
        }
    }

    private func textRow(_ item: [String: Any], at index: Int) -> some View {
        let title = item["title"] as? String ?? ""
        let accent = item["accent"] as? Bool ?? false
        let red = item["red"] as? Bool ?? false
        let clickable = (item["has_on_click"] as? Bool ?? false)
                    || (item["has_sub_fragment"] as? Bool ?? false)

        let titleColor: Color = red ? .red : (accent ? .accentColor : .primary)

        return Button(action: {
            guard clickable else { return }
            viewModel.click(atIndex: index)
        }) {
            HStack {
                iconView(item)
                Text(title).foregroundColor(titleColor)
                Spacer()
                if (item["has_sub_fragment"] as? Bool ?? false) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(!clickable)
    }

    @ViewBuilder
    private func iconView(_ item: [String: Any]) -> some View {
        let icon = item["icon"] as? String ?? ""
        if !icon.isEmpty, let img = UIImage(named: icon) {
            Image(uiImage: img)
                .renderingMode(.template)
                .foregroundColor(.accentColor)
                .frame(width: 24, height: 24)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Public entry point

@available(iOS 14.0, *)
public func egPluginSettingsController(context: AccountContext, plugin: EGPlugin) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let theme = presentationData.theme
    let strings = presentationData.strings

    let legacyController = LegacySwiftUIController(
        presentation: .navigation,
        theme: theme,
        strings: strings
    )
    legacyController.title = plugin.name
    legacyController.statusBar.statusBarStyle = theme.rootController.statusBarStyle.style

    let viewModel = PluginSettingsViewModel(pluginId: plugin.id)
    let swiftUIView = EGSwiftUIView<PluginSettingsView>(legacyController: legacyController, manageSafeArea: true) {
        PluginSettingsView(viewModel: viewModel, lang: strings.baseLanguageCode)
    }
    let hostingController = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: hostingController)
    return legacyController
}
