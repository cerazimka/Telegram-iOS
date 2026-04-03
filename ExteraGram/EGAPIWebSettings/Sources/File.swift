import Foundation

import EGAPIToken
import EGAPI
import EGLogging

import AccountContext

import EGSimpleSettings
import TelegramCore

public func updateSGWebSettingsInteractivelly(context: AccountContext) {
    let _ = getSGApiToken(context: context).startStandalone(next: { token in
        let _ = getSGSettings(token: token).startStandalone(next: { webSettings in
            EGLogger.shared.log("EGAPI", "New EGWebSettings for id \(context.account.peerId.id._internalGetInt64Value()): \(webSettings) ")
            EGSimpleSettings.shared.canUseStealthMode = webSettings.global.storiesAvailable
            EGSimpleSettings.shared.duckyAppIconAvailable = webSettings.global.duckyAppIconAvailable
            EGSimpleSettings.shared.canUseNY = webSettings.global.nyAvailable
            let _ = (context.account.postbox.transaction { transaction in
                updateAppConfiguration(transaction: transaction, { configuration -> AppConfiguration in
                    var configuration = configuration
                    configuration.sgWebSettings = webSettings
                    return configuration
                })
            }).startStandalone()
        }, error: { e in
            if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
                EGLogger.shared.log("EGAPI", errorMessage)
            }
        })
    }, error: { e in
        if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
            EGLogger.shared.log("EGAPI", errorMessage)
        }
    })
}


public func postSGWebSettingsInteractivelly(context: AccountContext, data: [String: Any]) {
    let _ = getSGApiToken(context: context).startStandalone(next: { token in
        let _ = postSGSettings(token: token, data: data).startStandalone(error: { e in
            if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
                EGLogger.shared.log("EGAPI", errorMessage)
            }
        })
    }, error: { e in
        if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
            EGLogger.shared.log("EGAPI", errorMessage)
        }
    })
}
