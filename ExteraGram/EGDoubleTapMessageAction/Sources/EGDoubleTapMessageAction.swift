import Foundation
import EGSimpleSettings
import Postbox
import TelegramCore


func sgDoubleTapMessageAction(incoming: Bool, message: Message) -> String {
    if incoming {
        return EGSimpleSettings.MessageDoubleTapAction.default.rawValue
    } else {
        return EGSimpleSettings.shared.messageDoubleTapActionOutgoing
    }
}
