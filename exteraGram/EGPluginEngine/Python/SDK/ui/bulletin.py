"""
Bulletin (toast-style notification) helpers for iOS plugins.

Two APIs are exposed:

    show_bulletin(title, text, icon)   — primitive iOS-side wrapper.

    BulletinHelper.show_success(msg)   — Android-compatible static helpers.
    BulletinHelper.show_error(msg)
    BulletinHelper.show_info(msg)
    BulletinHelper.show(msg, icon)
"""

import _ios_bridge


def show_bulletin(title: str, text: str = "", icon: str = "") -> None:
    """
    Show a Telegram-style bulletin notification.

    Args:
        title: Bold title text (or the only line when `text` is empty)
        text:  Optional subtitle text shown under the title
        icon:  Optional SF Symbol name (e.g. "checkmark.circle.fill")
    """
    try:
        _ios_bridge.show_bulletin(title, text, icon)
    except AttributeError:
        # Bridge not built with show_bulletin support — log instead.
        try:
            _ios_bridge.log_text(f"[Bulletin] {title}: {text}")
        except Exception:
            pass


class BulletinHelper:
    """
    Android-source-compatible bulletin helper. Static methods mirror the
    helper found in exteraGram for Android. Each call hops to the main
    thread inside the bridge, so callers don't need to dispatch themselves.
    """

    @staticmethod
    def show_success(message: str) -> None:
        show_bulletin(message, "", "checkmark.circle.fill")

    @staticmethod
    def show_error(message: str) -> None:
        show_bulletin(message, "", "xmark.octagon.fill")

    @staticmethod
    def show_info(message: str) -> None:
        show_bulletin(message, "", "info.circle.fill")

    @staticmethod
    def show(message: str, icon: str = "") -> None:
        """Generic single-line bulletin with custom (or no) SF Symbol icon."""
        show_bulletin(message, "", icon)

    @staticmethod
    def show_with_subtitle(title: str, subtitle: str, icon: str = "") -> None:
        """Two-line bulletin variant."""
        show_bulletin(title, subtitle, icon)
