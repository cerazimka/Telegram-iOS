"""
iOS-specific utilities. No Android equivalent — iOS-only plugins can use these directly.
"""

import _ios_bridge


def run_on_main_thread(func) -> None:
    """Schedule func on the iOS main thread."""
    _ios_bridge.run_on_main_thread(func)


def show_alert(title: str, message: str, button: str = "OK") -> None:
    """Show a UIAlertController with a single dismiss button."""
    try:
        _ios_bridge.show_alert(title, message, button)
    except AttributeError:
        pass


def show_toast(message: str, duration: float = 2.0) -> None:
    """Show a brief toast notification (bulletin-style)."""
    try:
        _ios_bridge.show_toast(message, duration)
    except AttributeError:
        pass


def open_url(url: str) -> None:
    """Open a URL in Safari or the in-app browser."""
    try:
        _ios_bridge.open_url(url)
    except AttributeError:
        pass


def copy_to_clipboard(text: str) -> None:
    """Copy text to the iOS pasteboard."""
    try:
        _ios_bridge.copy_to_clipboard(text)
    except AttributeError:
        pass


def haptic_feedback(style: str = "medium") -> None:
    """
    Trigger haptic feedback.
    style: "light" | "medium" | "heavy" | "success" | "warning" | "error"
    """
    try:
        _ios_bridge.haptic_feedback(style)
    except AttributeError:
        pass
