import Foundation
import UIKit
import SwiftUI
import AccountContext
import Display
import LegacyUI
import EGSwiftUI
import EGPluginEngine

// MARK: - Live log view

@available(iOS 14.0, *)
private final class PluginLogModel: ObservableObject {
    @Published var entries: [EGPluginDebugLog.Entry] = []
    private var observer: NSObjectProtocol?

    init() {
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: EGPluginDebugLog.changed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func reload() {
        entries = EGPluginDebugLog.shared.entries.reversed()
    }

    func clear() {
        EGPluginDebugLog.shared.clear()
    }

    var allText: String {
        EGPluginDebugLog.shared.entries
            .map { "[\($0.formattedTimestamp)] [\($0.tag)] \($0.message)" }
            .joined(separator: "\n")
    }
}

@available(iOS 14.0, *)
private struct PluginLogsView: View {
    @StateObject private var model = PluginLogModel()
    @State private var showCopied = false

    var body: some View {
        List {
            // ── Status ──────────────────────────────────────────────
            Section(header: Text("STATUS")) {
                statusRow("Python initialized", EGPythonBridge.isInitialized ? "YES ✓" : "NO ✗",
                          EGPythonBridge.isInitialized ? .green : .red)
                statusRow("Engine enabled", PluginsController.shared.isEngineEnabled ? "YES" : "NO",
                          PluginsController.shared.isEngineEnabled ? .green : .secondary)
                statusRow("Plugins total", "\(PluginsController.shared.plugins.count)", .secondary)
                let active = PluginsController.shared.plugins.filter { $0.isEnabled && !$0.isError }
                statusRow("Active (no error)", "\(active.count)", active.isEmpty ? .orange : .green)
                let errors = PluginsController.shared.plugins.filter { $0.isError }
                if !errors.isEmpty {
                    statusRow("With errors", "\(errors.count)", .red)
                }
            }

            // ── Installed plugins ───────────────────────────────────
            if !PluginsController.shared.plugins.isEmpty {
                Section(header: Text("PLUGINS")) {
                    ForEach(PluginsController.shared.plugins) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(p.name).font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text(p.isEnabled ? (p.isError ? "error" : "on") : "off")
                                    .font(.system(size: 12))
                                    .foregroundColor(p.isError ? .red : (p.isEnabled ? .green : .secondary))
                            }
                            if let msg = PluginsController.shared.pluginErrorMessage(p.id), !msg.isEmpty {
                                Text(msg)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.red)
                                    .lineLimit(3)
                            }
                            Text(p.filePath.isEmpty ? "no file path" : p.filePath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // ── Log stream ──────────────────────────────────────────
            Section(header:
                HStack {
                    Text("LOG (\(model.entries.count))")
                    Spacer()
                    Button("Copy") {
                        UIPasteboard.general.string = model.allText
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopied = false }
                    }
                    .font(.system(size: 13))
                    Button("Clear") { model.clear() }
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
            ) {
                if model.entries.isEmpty {
                    Text("No log entries yet.\nInstall or enable a plugin to see output.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    ForEach(model.entries) { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(entry.formattedTimestamp)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text("[\(entry.tag)]")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(colorFor(tag: entry.tag))
                            }
                            Text(entry.message)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .overlay(
            showCopied ? Text("Copied!").padding(8)
                .background(Color.black.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(8)
                .padding() : nil,
            alignment: .top
        )
    }

    @ViewBuilder
    private func statusRow(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 14))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(valueColor)
        }
    }

    private func colorFor(tag: String) -> Color {
        switch tag {
        case "Runtime": return .blue
        case "Engine":  return .orange
        case "Plugin":  return .purple
        default:        return .secondary
        }
    }
}

// MARK: - Entry point

public func egPluginLogsController(context: AccountContext) -> ViewController {
    guard #available(iOS 14.0, *) else {
        let vc = UIViewController()
        vc.title = "Plugin Logs"
        return LegacyController(presentation: .navigation, theme: nil)
    }

    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let theme   = presentationData.theme
    let strings = presentationData.strings

    let legacyController = LegacySwiftUIController(
        presentation: .navigation,
        theme: theme,
        strings: strings
    )
    legacyController.title = "Plugin Logs"
    legacyController.statusBar.statusBarStyle = theme.rootController.statusBarStyle.style

    let swiftUIView = EGSwiftUIView<PluginLogsView>(legacyController: legacyController) {
        PluginLogsView()
    }
    let hostingController = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: hostingController)

    return legacyController
}
