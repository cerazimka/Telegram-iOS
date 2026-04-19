import Foundation

import EGAPIToken
import EGAPI
import EGLogging

import AccountContext

import EGSimpleSettings
import TelegramCore

public func updateSGWebSettingsInteractivelly(context: AccountContext) {
    let _ = getEGApiToken(context: context).startStandalone(next: { token in
        let _ = getEGSettings(token: token).startStandalone(next: { webSettings in
            EGLogger.shared.log("SGAPI", "New EGWebSettings for id \(context.account.peerId.id._internalGetInt64Value()): \(webSettings) ")
            EGSimpleSettings.shared.canUseStealthMode = webSettings.global.storiesAvailable
            EGSimpleSettings.shared.duckyAppIconAvailable = webSettings.global.duckyAppIconAvailable
            EGSimpleSettings.shared.canUseNY = webSettings.global.nyAvailable
            let _ = (context.account.postbox.transaction { transaction in
                updateAppConfiguration(transaction: transaction, { configuration -> AppConfiguration in
                    var configuration = configuration
                    configuration.egWebSettings = webSettings
                    return configuration
                })
            }).startStandalone()
        }, error: { e in
            if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
                EGLogger.shared.log("SGAPI", errorMessage)
            }
        })
    }, error: { e in
        if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
            EGLogger.shared.log("SGAPI", errorMessage)
        }
    })
}


public func postSGWebSettingsInteractivelly(context: AccountContext, data: [String: Any]) {
    let _ = getEGApiToken(context: context).startStandalone(next: { token in
        let _ = postEGSettings(token: token, data: data).startStandalone(error: { e in
            if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
                EGLogger.shared.log("SGAPI", errorMessage)
            }
        })
    }, error: { e in
        if case let .generic(errorMessage) = e, let errorMessage = errorMessage {
            EGLogger.shared.log("SGAPI", errorMessage)
        }
    })
}
