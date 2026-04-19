// MARK: exteraGram
import EGLogging
import EGAppGroupIdentifier
import EGSimpleSettings
import SwiftSignalKit
import TelegramUIPreferences
import AccountContext
import Postbox
import Foundation

extension SharedAccountContextImpl {
    // MARK: exteraGram
    func performEGUISettingsMigrationIfNecessary() {
        if self.didPerformEGUISettingsMigration {
            return
        }
        let sgMigrationKey = "sg_migrated_sgui_settings_v1"
        if UserDefaults.standard.bool(forKey: sgMigrationKey) {
            self.didPerformEGUISettingsMigration = true
            return
        }
        guard let sgPrimary = self.sgPrimaryAccountContextForMigration() else {
            return
        }
        self.didPerformEGUISettingsMigration = true
        
        let sgPreferences: Signal<PreferencesView, NoError> = sgPrimary.account.postbox.preferencesView(keys: [ApplicationSpecificPreferencesKeys.EGUISettings])
        let _ = (sgPreferences
        |> take(1)
        |> deliverOnMainQueue).start(next: { view in
            let sgSettings: EGUISettings = view.values[ApplicationSpecificPreferencesKeys.EGUISettings]?.get(EGUISettings.self) ?? .default
            let sgDefaults = UserDefaults.standard
            let sgDomainName = egBaseBundleIdentifier()
            let sgDomain = sgDefaults.persistentDomain(forName: sgDomainName) ?? [:]
            if sgDomain[EGSimpleSettings.Keys.hideStories.rawValue] == nil {
                EGSimpleSettings.shared.hideStories = sgSettings.hideStories
                EGLogger.shared.log("EGSimpleSettings", "Migrated hideStories: \(sgSettings.hideStories)")
            }
            if sgDomain[EGSimpleSettings.Keys.warnOnStoriesOpen.rawValue] == nil {
                EGSimpleSettings.shared.warnOnStoriesOpen = sgSettings.warnOnStoriesOpen
                EGLogger.shared.log("EGSimpleSettings", "Migrated warnOnStoriesOpen: \(sgSettings.warnOnStoriesOpen)")
            }
            if sgDomain[EGSimpleSettings.Keys.showProfileId.rawValue] == nil {
                EGSimpleSettings.shared.showProfileId = sgSettings.showProfileId
                EGLogger.shared.log("EGSimpleSettings", "Migrated showProfileId: \(sgSettings.showProfileId)")
            }
            if sgDomain[EGSimpleSettings.Keys.sendWithReturnKey.rawValue] == nil {
                EGSimpleSettings.shared.sendWithReturnKey = sgSettings.sendWithReturnKey
                EGLogger.shared.log("EGSimpleSettings", "Migrated sendWithReturnKey: \(sgSettings.sendWithReturnKey)")
            }
            sgDefaults.set(true, forKey: sgMigrationKey)
        })
    }
}
