"""
Menu integration API. Plugins register items that the host UI can pick up
and render in its drawer / context / chat menus.

Usage:

    from base_plugin import BasePlugin
    from menu import MenuItemData, MenuItemType

    class MyPlugin(BasePlugin):
        def on_plugin_load(self):
            self.add_menu_item(MenuItemData(
                menu_type=MenuItemType.DRAWER_MENU,
                text="Restart App",
                icon="msg_retry",
                priority=150,
                on_click=self._on_restart,
            ))

        def _on_restart(self, context):
            self.log("restart tapped")

The Swift side queries `PluginsController.shared.menuItems(of:)` for each
menu surface it renders and dispatches taps back via `invokeMenuItemClick(_:)`.
"""

from dataclasses import dataclass
from typing import Optional, Callable, Any


class MenuItemType:
    """Surface where a menu item should appear. Matches the Android constants."""
    DRAWER_MENU   = "drawer"
    CONTEXT_MENU  = "context"      # message context menu
    SETTINGS_MENU = "settings"     # app-wide settings list
    PROFILE_MENU  = "profile"
    CHAT_MENU     = "chat"


@dataclass
class MenuItemData:
    menu_type: str = MenuItemType.DRAWER_MENU
    text: str = ""
    icon: str = ""
    priority: int = 0
    accent: bool = False
    red: bool = False
    link_alias: str = ""
    on_click: Optional[Callable[[Any], None]] = None

    def to_dict(self) -> dict:
        """Serialise to a dict consumable by the Swift renderer."""
        return {
            "menu_type": self.menu_type,
            "text":      self.text,
            "icon":      self.icon,
            "priority":  self.priority,
            "accent":    self.accent,
            "red":       self.red,
            "link_alias": self.link_alias,
        }
