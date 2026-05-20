// MARK: exteraGram — bridges Python i18n → EGLocalizationManager

import Foundation
import EGStrings

/// Called from EGIOSBridge.m for Python get_locale_language() calls.
/// ObjC calls this via a notification or direct @objc method.
@objc public final class EGStringsBridgeImpl: NSObject {
    @objc public static func currentLanguage() -> String {
        return EGLocalizationManager.shared.sanitizeLocale(
            Locale.current.languageCode ?? "en"
        )
    }

    @objc public static func localizedString(_ key: String) -> String {
        return i18n(key)
    }
}
