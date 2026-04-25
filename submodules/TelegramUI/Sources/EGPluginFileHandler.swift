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

// MARK: - SwiftUI Bottom Sheet

@available(iOS 14.0, *)
private struct EGPluginInstallSheet: View {
    let metadata: EGPluginFileMetadata
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    // Drag handle
                    Capsule()
                        .fill(Color(UIColor.tertiaryLabel))
                        .frame(width: 36, height: 4)
                        .padding(.top, 8)
                        .padding(.bottom, 20)

                    // Plugin icon — 78pt circle with puzzle piece
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 78, height: 78)
                        Image(systemName: "puzzlepiece.extension.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.white)
                    }
                    .padding(.bottom, 16)

                    // Plugin name
                    Text(metadata.name ?? "Plugin")
                        .font(.system(size: 18, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 4)

                    // Version · Author
                    if metadata.version != nil || metadata.author != nil {
                        HStack(spacing: 0) {
                            if let version = metadata.version {
                                Text("v\(version)")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                            if metadata.version != nil && metadata.author != nil {
                                Text(" · ")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(UIColor.tertiaryLabel))
                            }
                            if let author = metadata.author {
                                Text(author)
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        }
                        .padding(.bottom, 12)
                    }

                    // Trust badge — always "Unknown source" until we have verification
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 12))
                        Text("Unknown source")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Color(UIColor.systemOrange))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.systemOrange).opacity(0.12))
                    .clipShape(Capsule())
                    .padding(.bottom, 28)

                    // Description
                    if let description = metadata.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 15))
                            .foregroundColor(Color(UIColor.label))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 21)
                            .padding(.bottom, 28)
                    }

                    // Install button
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Text("Install Plugin")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                    // Safe area bottom padding
                    Color.clear.frame(height: 16)
                }
            }

            // Close button — top right, matches Android's "open in" position
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(UIColor.secondaryLabel))
                    .frame(width: 30, height: 30)
                    .background(Color(UIColor.tertiarySystemFill))
                    .clipShape(Circle())
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .background(Color(UIColor.systemBackground))
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
            let sheet = UIHostingController(rootView: EGPluginInstallSheet(metadata: metadata))
            sheet.modalPresentationStyle = .overFullScreen
            sheet.view.backgroundColor = .clear

            if #available(iOS 16.0, *) {
                sheet.modalPresentationStyle = .pageSheet
                if let sheetController = sheet.sheetPresentationController {
                    sheetController.detents = [.medium(), .large()]
                    sheetController.prefersGrabberVisible = false  // we draw our own
                    sheetController.preferredCornerRadius = 16
                }
            }
            rootController.present(sheet, animated: true)
        } else {
            // iOS 13 fallback: alert with key metadata
            let lines = [
                metadata.name.map { "Plugin: \($0)" },
                metadata.author.map { "Author: \($0)" },
                metadata.version.map { "Version: \($0)" },
                metadata.description.map { "\($0)" }
            ].compactMap { $0 }
            let alert = UIAlertController(
                title: metadata.name ?? "Plugin Info",
                message: lines.dropFirst().joined(separator: "\n"),
                preferredStyle: .actionSheet
            )
            alert.addAction(UIAlertAction(title: "Install", style: .default))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            rootController.present(alert, animated: true)
        }
    })
}
