// MARK: exteraGram — Bulletin / toast presenter for plugin notifications
//
// Listens for EGPluginShowBulletinNotification (title/text/icon) and
// EGPluginShowToastNotification (message/duration) posted by EGIOSBridge,
// and renders a Telegram-style bulletin overlay on the active key window.
//
// Self-contained UIKit: no AccountContext / PresentationData required, so
// the host can live in EGPluginEngine without pulling in EGSettingsUI's
// dependency cone.

import Foundation
import UIKit
import EGLogging

@objc public final class EGPluginBulletinHost: NSObject {
    @objc public static let shared = EGPluginBulletinHost()

    private var started = false

    private override init() { super.init() }

    /// Begin listening. Idempotent — safe to call from every engine start.
    @objc public func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleBulletin(_:)),
            name: NSNotification.Name("EGPluginShowBulletinNotification"),
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleToast(_:)),
            name: NSNotification.Name("EGPluginShowToastNotification"),
            object: nil
        )
        EGLogger.shared.log("PluginEngine", "Bulletin host listening")
    }

    @objc private func handleBulletin(_ note: Notification) {
        let userInfo = note.userInfo ?? [:]
        let title = (userInfo["title"] as? String) ?? ""
        let text  = (userInfo["text"]  as? String) ?? ""
        let icon  = (userInfo["icon"]  as? String) ?? ""
        DispatchQueue.main.async {
            self.present(title: title, text: text, icon: icon, duration: 3.0)
        }
    }

    @objc private func handleToast(_ note: Notification) {
        let userInfo = note.userInfo ?? [:]
        let message = (userInfo["message"] as? String) ?? ""
        let duration = (userInfo["duration"] as? Double) ?? 2.0
        DispatchQueue.main.async {
            self.present(title: message, text: "", icon: "", duration: duration)
        }
    }

    // MARK: - Presentation

    private func present(title: String, text: String, icon: String, duration: TimeInterval) {
        guard let window = topKeyWindow() else { return }
        let bulletin = BulletinView(title: title, text: text, iconName: icon)
        bulletin.translatesAutoresizingMaskIntoConstraints = false
        bulletin.alpha = 0
        bulletin.transform = CGAffineTransform(translationX: 0, y: 32)

        window.addSubview(bulletin)
        NSLayoutConstraint.activate([
            bulletin.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            bulletin.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            bulletin.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: 16),
            bulletin.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -16),
        ])

        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut], animations: {
            bulletin.alpha = 1
            bulletin.transform = .identity
        }, completion: { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                UIView.animate(withDuration: 0.22, animations: {
                    bulletin.alpha = 0
                    bulletin.transform = CGAffineTransform(translationX: 0, y: 32)
                }, completion: { _ in
                    bulletin.removeFromSuperview()
                })
            }
        })
    }

    private func topKeyWindow() -> UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene,
                  ws.activationState == .foregroundActive else { continue }
            if let key = ws.windows.first(where: { $0.isKeyWindow }) { return key }
            if let first = ws.windows.first { return first }
        }
        return UIApplication.shared.windows.first(where: { $0.isKeyWindow })
            ?? UIApplication.shared.windows.first
    }
}

// MARK: - Bulletin view

private final class BulletinView: UIView {
    init(title: String, text: String, iconName: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor.secondarySystemBackground
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.shadowRadius = 12

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        if !iconName.isEmpty,
           let icon = UIImage(systemName: iconName) ?? UIImage(named: iconName) {
            let iv = UIImageView(image: icon.withRenderingMode(.alwaysTemplate))
            iv.tintColor = .systemBlue
            iv.contentMode = .scaleAspectFit
            iv.setContentHuggingPriority(.required, for: .horizontal)
            iv.widthAnchor.constraint(equalToConstant: 26).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 26).isActive = true
            stack.addArrangedSubview(iv)
        }

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.numberOfLines = 2
        titleLabel.textColor = .label
        textStack.addArrangedSubview(titleLabel)

        if !text.isEmpty {
            let subLabel = UILabel()
            subLabel.text = text
            subLabel.font = UIFont.systemFont(ofSize: 13)
            subLabel.textColor = .secondaryLabel
            subLabel.numberOfLines = 3
            textStack.addArrangedSubview(subLabel)
        }

        stack.addArrangedSubview(textStack)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
