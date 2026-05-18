// MARK: exteraGram — .plugin file metadata display

import Foundation
import UIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import Display
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import StickerResources
import EGSettingsUI
import ComponentFlow
import GlassBackgroundComponent

// MARK: - Metadata Model

struct EGPluginFileMetadata {
    var id: String?
    var name: String?
    var description: String?
    var author: String?
    var version: String?
    var icon: String?
    var requirements: [String] = []
    var appVersion: String?
    var sdkVersion: String?

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
            case "icon":
                if let slash = value.lastIndex(of: "/"),
                   Int(value[value.index(after: slash)...]) != nil {
                    meta.icon = value
                }
            case "requirements":
                meta.requirements = value.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            case "app_version": meta.appVersion = value
            case "sdk_version": meta.sdkVersion = value
            default:            break
            }
        }
        return meta
    }

    private static func parseLine(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
        guard let eqIdx = trimmed.firstIndex(of: "=") else { return nil }
        let rawKey = String(trimmed[trimmed.startIndex..<eqIdx])
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let valuePart = String(trimmed[trimmed.index(after: eqIdx)...])
            .trimmingCharacters(in: .whitespaces)
        guard !rawKey.isEmpty, !valuePart.isEmpty else { return nil }
        for quote: Character in ["\"", "'"] {
            let q = String(quote)
            guard valuePart.hasPrefix(q) else { continue }
            let afterOpen = String(valuePart.dropFirst())
            guard let closeRange = afterOpen.range(of: q) else { continue }
            return (rawKey, String(afterOpen[afterOpen.startIndex..<closeRange.lowerBound]))
        }
        return nil
    }
}

// MARK: - Glass circle button (same component as ChatRankInfoScreen close button)

private final class EGGlassCircleButtonView: UIView {
    private let glass = GlassBackgroundView()
    private let imageView: UIImageView
    var tapAction: (() -> Void)?

    init(systemImage: String) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        imageView = UIImageView(image: UIImage(systemName: systemImage, withConfiguration: cfg))
        super.init(frame: .zero)
        glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(glass)
        imageView.tintColor = .white
        imageView.contentMode = .center
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() { tapAction?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sz = bounds.size
        guard sz.width > 0, sz.height > 0 else { return }
        glass.frame = bounds
        imageView.frame = bounds
        glass.update(
            size: sz, cornerRadius: sz.height / 2,
            isDark: traitCollection.userInterfaceStyle == .dark,
            tintColor: .init(kind: .panel),
            isInteractive: true, transition: .immediate
        )
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { setNeedsLayout() }
    }
}

// MARK: - Glass install button (same style as ChatRankInfoScreen action button)

private final class EGGlassInstallButtonView: UIView {
    private let glass = GlassBackgroundView()
    private let label = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    var tapAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(glass)
        label.text = "Install"
        label.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(label)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        addSubview(spinner)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() { tapAction?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let sz = bounds.size
        guard sz.width > 0, sz.height > 0 else { return }
        glass.frame = bounds
        label.frame = bounds
        spinner.center = CGPoint(x: sz.width / 2, y: sz.height / 2)
        glass.update(
            size: sz, cornerRadius: sz.height / 2,
            isDark: traitCollection.userInterfaceStyle == .dark,
            tintColor: .init(kind: .panel, innerColor: UIColor.systemBlue.withAlphaComponent(0.45)),
            isInteractive: true, transition: .immediate
        )
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { setNeedsLayout() }
    }

    func setInstalling(_ installing: Bool) {
        isUserInteractionEnabled = !installing
        alpha = installing ? 0.6 : 1.0
        label.isHidden = installing
        if installing { spinner.startAnimating() } else { spinner.stopAnimating() }
    }
}

// MARK: - Plugin Install Alert

private final class EGPluginAlertViewController: UIViewController {
    private let metadata: EGPluginFileMetadata
    private let filePath: String
    private let accountContext: AccountContext

    private let dimView = UIView()
    private let cardView = UIView()

    // Top glass buttons (like ChatRankInfoScreen)
    private let closeButton = EGGlassCircleButtonView(systemImage: "xmark")
    private let shareButton = EGGlassCircleButtonView(systemImage: "square.and.arrow.up")

    // Content
    private let iconContainerView = UIView()
    private let nameLabel = UILabel()
    private let authorLabel = UILabel()
    private let pillView = UIView()
    private let pillIconView = UIImageView()
    private let pillTextLabel = UILabel()
    private let requirementsLabel = UILabel()

    // Bottom glass install button (like ChatRankInfoScreen action button)
    private let installButton = EGGlassInstallButtonView()

    private var isInstalling = false
    private var stickerNode: DefaultAnimatedStickerNodeImpl?
    private var packDisposable: Disposable?
    private var fetchDisposable: Disposable?

    init(metadata: EGPluginFileMetadata, filePath: String, context: AccountContext) {
        self.metadata = metadata
        self.filePath = filePath
        self.accountContext = context
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        let node = stickerNode
        let d1 = packDisposable
        let d2 = fetchDisposable
        // ASDisplayKit nodes and TelegramCore signal disposal must happen on the main thread.
        if Thread.isMainThread {
            node?.view.removeFromSuperview()
            d1?.dispose()
            d2?.dispose()
        } else {
            DispatchQueue.main.async {
                node?.view.removeFromSuperview()
                d1?.dispose()
                d2?.dispose()
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimView.backgroundColor = UIColor(white: 0, alpha: 0.4)
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimView.frame = view.bounds
        view.addSubview(dimView)
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeTapped)))

        cardView.backgroundColor = UIColor.secondarySystemGroupedBackground
        cardView.layer.cornerRadius = 14
        cardView.layer.masksToBounds = true
        view.addSubview(cardView)

        // Top glass buttons
        closeButton.tapAction = { [weak self] in self?.closeTapped() }
        shareButton.tapAction = { [weak self] in self?.shareTapped() }
        cardView.addSubview(closeButton)
        cardView.addSubview(shareButton)

        // Icon
        iconContainerView.backgroundColor = UIColor.systemBlue
        iconContainerView.layer.cornerRadius = 18
        iconContainerView.clipsToBounds = true
        let symCfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        let fallback = UIImageView(image: UIImage(systemName: "puzzlepiece.extension.fill", withConfiguration: symCfg))
        fallback.tintColor = .white
        fallback.contentMode = .center
        fallback.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        iconContainerView.addSubview(fallback)
        cardView.addSubview(iconContainerView)
        if let iconStr = metadata.icon, !iconStr.isEmpty { loadStickerIcon(iconStr) }

        // Name
        nameLabel.text = metadata.name ?? "Plugin"
        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.textColor = .label
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        cardView.addSubview(nameLabel)

        // Author/version
        let parts = [metadata.version, metadata.author].compactMap { $0 }.filter { !$0.isEmpty }
        authorLabel.text = parts.joined(separator: " · ")
        authorLabel.font = .systemFont(ofSize: 13)
        authorLabel.textColor = .secondaryLabel
        authorLabel.textAlignment = .center
        authorLabel.numberOfLines = 2
        authorLabel.isHidden = parts.isEmpty
        cardView.addSubview(authorLabel)

        // Unknown source pill
        pillView.backgroundColor = .systemRed
        pillView.layer.masksToBounds = true
        let pillSymCfg = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        pillIconView.image = UIImage(systemName: "questionmark.circle.fill", withConfiguration: pillSymCfg)
        pillIconView.tintColor = .white
        pillIconView.contentMode = .scaleAspectFit
        pillTextLabel.text = "Unknown source"
        pillTextLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        pillTextLabel.textColor = .white
        pillView.addSubview(pillIconView)
        pillView.addSubview(pillTextLabel)
        cardView.addSubview(pillView)

        // Requirements
        requirementsLabel.text = metadata.requirements.joined(separator: "  •  ")
        requirementsLabel.font = .systemFont(ofSize: 11)
        requirementsLabel.textColor = .secondaryLabel
        requirementsLabel.textAlignment = .center
        requirementsLabel.numberOfLines = 0
        requirementsLabel.isHidden = metadata.requirements.isEmpty
        cardView.addSubview(requirementsLabel)

        // Install button
        installButton.tapAction = { [weak self] in self?.installTapped() }
        cardView.addSubview(installButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCard()
    }

    private func layoutCard() {
        let cardW: CGFloat = 270
        let hPad: CGFloat = 16
        let btnSide: CGFloat = 44
        let iconSide: CGFloat = 60
        var y: CGFloat = 0

        // Top glass buttons row
        closeButton.frame = CGRect(x: hPad, y: hPad, width: btnSide, height: btnSide)
        shareButton.frame = CGRect(x: cardW - hPad - btnSide, y: hPad, width: btnSide, height: btnSide)
        y = hPad + btnSide + 12

        // Icon
        iconContainerView.frame = CGRect(x: (cardW - iconSide) / 2, y: y, width: iconSide, height: iconSide)
        y += iconSide + 10

        // Name
        let tw = cardW - hPad * 2
        let nameH = ceil(nameLabel.sizeThatFits(CGSize(width: tw, height: 200)).height)
        nameLabel.frame = CGRect(x: hPad, y: y, width: tw, height: nameH)
        y += nameH + 2

        // Author
        if !authorLabel.isHidden {
            let ah = ceil(authorLabel.sizeThatFits(CGSize(width: tw, height: 100)).height)
            authorLabel.frame = CGRect(x: hPad, y: y, width: tw, height: ah)
            y += ah
        }
        y += 10

        // Pill
        let pillH: CGFloat = 22
        let iconW: CGFloat = 12
        let tsz = pillTextLabel.sizeThatFits(CGSize(width: 200, height: pillH))
        let pp: CGFloat = 10
        let pillW = pp + iconW + 4 + tsz.width + pp
        pillView.frame = CGRect(x: (cardW - pillW) / 2, y: y, width: pillW, height: pillH)
        pillView.layer.cornerRadius = pillH / 2
        pillIconView.frame = CGRect(x: pp, y: (pillH - iconW) / 2, width: iconW, height: iconW)
        pillTextLabel.frame = CGRect(x: pp + iconW + 4, y: (pillH - tsz.height) / 2, width: tsz.width, height: tsz.height)
        y += pillH + 8

        // Requirements
        if !requirementsLabel.isHidden {
            let rh = ceil(requirementsLabel.sizeThatFits(CGSize(width: tw, height: 100)).height)
            requirementsLabel.frame = CGRect(x: hPad, y: y, width: tw, height: rh)
            y += rh + 8
        }

        y += 12
        // Install button (capsule, full-width minus margins, 50pt tall)
        let installH: CGFloat = 50
        installButton.frame = CGRect(x: hPad, y: y, width: cardW - hPad * 2, height: installH)
        y += installH + 20

        let cardH = y
        cardView.frame = CGRect(
            x: (view.bounds.width - cardW) / 2,
            y: (view.bounds.height - cardH) / 2,
            width: cardW,
            height: cardH
        )
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func shareTapped() {
        let avc = UIActivityViewController(activityItems: [URL(fileURLWithPath: filePath)], applicationActivities: nil)
        avc.popoverPresentationController?.sourceView = shareButton
        present(avc, animated: true)
    }

    private func installTapped() {
        guard !isInstalling else { return }
        isInstalling = true
        installButton.setInstalling(true)

        let meta = metadata
        let fp = filePath

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let pluginId = meta.id ?? UUID().uuidString

            if let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let pluginsDir = supportDir.appendingPathComponent("EGPlugins", isDirectory: true)
                try? fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
                let destURL = pluginsDir.appendingPathComponent("\(pluginId).plugin")
                try? fm.removeItem(at: destURL)
                try? fm.copyItem(atPath: fp, toPath: destURL.path)
            }

            let plugin = EGPlugin(
                id: pluginId,
                name: meta.name ?? "Unknown Plugin",
                subtitle: meta.author ?? "",
                pluginDescription: meta.description ?? "",
                version: meta.version ?? "1.0",
                iconUrl: meta.icon,
                isEnabled: true,
                requiresPermissions: meta.requirements
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var plugins = PluginsController.shared.plugins
                if let idx = plugins.firstIndex(where: { $0.id == pluginId }) {
                    plugins[idx] = plugin
                } else {
                    plugins.append(plugin)
                }
                PluginsController.shared.plugins = plugins
                self.dismiss(animated: true)
            }
        }
    }

    private func loadStickerIcon(_ iconStr: String) {
        guard let slashIdx = iconStr.lastIndex(of: "/"),
              let index = Int(iconStr[iconStr.index(after: slashIdx)...]) else { return }
        let packName = String(iconStr[iconStr.startIndex..<slashIdx])
        let size: CGFloat = 60
        let iconSize = CGSize(width: size, height: size)
        let pixelSide = Int(size * UIScreen.main.scale)

        packDisposable = (accountContext.engine.stickers.loadedStickerPack(
                reference: .name(packName), forceActualized: false)
            |> deliverOnMainQueue
        ).startStandalone(next: { [weak self] result in
            guard let self, self.stickerNode == nil else { return }
            guard case .result(_, let items, _) = result, index < items.count else { return }
            let file = items[index].file._parse()
            let node = DefaultAnimatedStickerNodeImpl()
            node.setup(
                source: AnimatedStickerResourceSource(
                    account: self.accountContext.account,
                    resource: file.resource,
                    isVideo: file.isVideoSticker
                ),
                width: pixelSide, height: pixelSide,
                playbackMode: .loop, mode: .direct(cachePathPrefix: nil)
            )
            node.updateLayout(size: iconSize)
            node.overrideVisibility = true
            node.visibility = true
            node.frame = CGRect(origin: .zero, size: iconSize)
            node.view.frame = CGRect(origin: .zero, size: iconSize)
            self.iconContainerView.addSubview(node.view)
            self.stickerNode = node

            self.fetchDisposable = freeMediaFileResourceInteractiveFetched(
                account: self.accountContext.account,
                userLocation: .other,
                fileReference: stickerPackFileReference(file),
                resource: file.resource
            ).startStandalone()
        })
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
              let text = try? String(contentsOfFile: data.path, encoding: .utf8) else { return }
        let metadata = EGPluginFileMetadata.parse(from: text)
        guard !metadata.isEmpty else { return }
        guard let rootController = navigationController?.view.window?.rootViewController else { return }

        let vc = EGPluginAlertViewController(metadata: metadata, filePath: data.path, context: context)
        rootController.present(vc, animated: true)
    })
}
