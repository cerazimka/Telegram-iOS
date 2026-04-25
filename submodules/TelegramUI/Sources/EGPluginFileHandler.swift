// MARK: exteraGram — .plugin file metadata display

import Foundation
import UIKit
import SwiftUI
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext

// MARK: - Metadata Model

struct EGPluginFileMetadata {
    var id: String?
    var name: String?
    var description: String?
    var author: String?
    var version: String?
    var icon: String?

    var isEmpty: Bool {
        return id == nil && name == nil && description == nil && author == nil && version == nil
    }

    static func parse(from text: String) -> EGPluginFileMetadata {
        var meta = EGPluginFileMetadata()
        for line in text.components(separatedBy: .newlines) {
            guard let (key, value) = parseLine(line) else { continue }
            switch key {
            case "id":          meta.id = value
            case "name":        meta.name = value
            case "description": meta.description = value
            case "author":      meta.author = value
            case "version":     meta.version = value
            case "icon":        meta.icon = value
            default:            break
            }
        }
        return meta
    }

    // Parses lines of the form:  __key__ = "value"
    private static func parseLine(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("__") else { return nil }
        let separator = "__ = \""
        guard let sepRange = trimmed.range(of: separator) else { return nil }
        let key = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<sepRange.lowerBound])
        guard !key.isEmpty else { return nil }
        let remaining = String(trimmed[sepRange.upperBound...])
        guard remaining.hasSuffix("\"") else { return nil }
        return (key, String(remaining.dropLast()))
    }
}

// MARK: - SwiftUI Sheet

@available(iOS 14.0, *)
private struct EGPluginMetadataSheet: View {
    let metadata: EGPluginFileMetadata
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 56, height: 56)
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 26))
                                .foregroundColor(.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metadata.name ?? "Plugin")
                                .font(.headline)
                            if let author = metadata.author {
                                Text(author)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }

                if metadata.id != nil || metadata.version != nil {
                    Section {
                        if let id = metadata.id {
                            metaRow(label: "ID", value: id)
                        }
                        if let version = metadata.version {
                            metaRow(label: "Version", value: version)
                        }
                    }
                }

                if let desc = metadata.description {
                    Section(header: Text("Description")) {
                        Text(desc)
                            .font(.body)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Plugin Info")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Presentation Helper

func presentEGPluginMetadataIfAvailable(
    file: TelegramMediaFile,
    context: AccountContext,
    navigationController: UINavigationController?
) {
    let _ = (context.account.postbox.mediaBox.resourceData(file.resource, option: .complete(waitUntilFetchStatus: true))
    |> take(1)
    |> deliverOnMainQueue).startStandalone(next: { data in
        guard data.complete,
              let text = try? String(contentsOfFile: data.path, encoding: .utf8) else {
            return
        }
        let metadata = EGPluginFileMetadata.parse(from: text)
        guard !metadata.isEmpty else { return }

        guard let rootController = navigationController?.view.window?.rootViewController else { return }

        if #available(iOS 14.0, *) {
            let sheet = UIHostingController(rootView: EGPluginMetadataSheet(metadata: metadata))
            if #available(iOS 16.0, *) {
                if let sheetController = sheet.sheetPresentationController {
                    sheetController.detents = [.medium(), .large()]
                    sheetController.prefersGrabberVisible = true
                }
            }
            rootController.present(sheet, animated: true)
        } else {
            let lines = [
                metadata.name.map { "Name: \($0)" },
                metadata.author.map { "Author: \($0)" },
                metadata.version.map { "Version: \($0)" },
                metadata.description.map { "Description: \($0)" }
            ].compactMap { $0 }
            let alert = UIAlertController(
                title: metadata.name ?? "Plugin Info",
                message: lines.dropFirst().joined(separator: "\n"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            rootController.present(alert, animated: true)
        }
    })
}
