"""
Plugin settings UI.

Provides a small declarative DSL that matches the exteraGram Android SDK so
plugins can reuse their `create_settings()` body verbatim:

    from ui.settings import Header, Switch, Selector, Input, Text, Divider

    class MyPlugin(BasePlugin):
        def create_settings(self):
            return [
                Header(text="General"),
                Switch(key="big", text="Big reactions", default=False, icon="msg_emoji"),
                Selector(key="lang", text="Language",
                         items=["English", "Русский"], default=0,
                         on_change=self._on_lang_changed),
                Input(key="api_key", text="API key", default=""),
                Divider(text="Restart required after changing the API key."),
                Text(text="Reset", red=True, icon="msg_delete",
                     on_click=self._reset_all),
            ]

The Swift renderer (TODO) consumes the dict produced by `PluginSettings.to_dict()`.
Until that lands, the SDK still stores items so list contents are accessible
for debugging via `__settings__.items`.
"""

from dataclasses import dataclass, field
from typing import Any, List, Optional, Callable


# Setting item kinds — values must match what the Swift renderer expects.
KIND_HEADER   = "header"
KIND_SWITCH   = "switch"
KIND_SELECTOR = "selector"
KIND_INPUT    = "input"
KIND_TEXT     = "text"
KIND_DIVIDER  = "divider"
KIND_SLIDER   = "slider"

# Legacy alias kept for backwards compatibility with the original SDK shape.
KIND_TOGGLE   = "toggle"


@dataclass
class SettingItem:
    """
    Generic setting row. Most plugins use the higher-level factory functions
    (`Header`, `Switch`, ...) below; SettingItem is the underlying record.
    """
    # Required for the renderer to pick the right cell
    type: str = KIND_SWITCH

    # Identity / persistence
    key: str = ""

    # Display
    title: str = ""        # Primary text (also used as section title for headers)
    subtitle: str = ""     # Secondary text under the row
    icon: str = ""         # Image asset name (e.g. "msg_settings")
    accent: bool = False   # Render the title in the accent (blue) colour
    red: bool = False      # Render the title in destructive (red) colour
    link_alias: str = ""   # Deep-link slug used by Android plugins; informational on iOS

    # Value / defaults
    default: Any = None
    options: List[Any] = field(default_factory=list)  # for selector
    min_value: Optional[float] = None                 # for slider
    max_value: Optional[float] = None                 # for slider

    # Callbacks (not serialised to dict; resolved at runtime)
    on_change:     Optional[Callable[[Any], None]]  = None
    on_click:      Optional[Callable[[Any], None]]  = None
    on_long_click: Optional[Callable[[Any], None]]  = None

    # Optional nested screen builder — returns a list of SettingItems.
    # Honoured by the Swift renderer when it lands; ignored for now.
    create_sub_fragment: Optional[Callable[[], list]] = None

    def to_dict(self) -> dict:
        """Serialise to a dict the Swift renderer can consume."""
        d = {
            "type": self.type,
            "key": self.key,
            "title": self.title,
            "subtitle": self.subtitle,
            "icon": self.icon,
            "accent": self.accent,
            "red": self.red,
            "link_alias": self.link_alias,
            "default": self.default,
            "options": list(self.options),
            "has_sub_fragment": self.create_sub_fragment is not None,
        }
        if self.min_value is not None: d["min_value"] = self.min_value
        if self.max_value is not None: d["max_value"] = self.max_value
        return d


# ---------------------------------------------------------------------------
# Factory functions — Android-source compatible names
# ---------------------------------------------------------------------------

def Header(text: str = "", **kwargs) -> SettingItem:
    """Section header. `text` is the section title."""
    return SettingItem(type=KIND_HEADER, title=text, **kwargs)


def Switch(key: str, text: str, default: bool = False,
           subtext: str = "", icon: str = "", link_alias: str = "",
           on_change: Optional[Callable[[Any], None]] = None,
           **kwargs) -> SettingItem:
    """Boolean toggle row."""
    return SettingItem(
        type=KIND_SWITCH, key=key, title=text, subtitle=subtext,
        default=bool(default), icon=icon, link_alias=link_alias,
        on_change=on_change, **kwargs,
    )


def Selector(key: str, text: str, items: List[Any], default: int = 0,
             subtext: str = "", icon: str = "", link_alias: str = "",
             on_change: Optional[Callable[[Any], None]] = None,
             **kwargs) -> SettingItem:
    """Single-choice picker. `items` is a list of display strings."""
    return SettingItem(
        type=KIND_SELECTOR, key=key, title=text, subtitle=subtext,
        default=default, options=list(items), icon=icon, link_alias=link_alias,
        on_change=on_change, **kwargs,
    )


def Input(key: str, text: str, default: str = "",
          subtext: str = "", icon: str = "", link_alias: str = "",
          on_change: Optional[Callable[[Any], None]] = None,
          **kwargs) -> SettingItem:
    """Free-form text input."""
    return SettingItem(
        type=KIND_INPUT, key=key, title=text, subtitle=subtext,
        default=str(default), icon=icon, link_alias=link_alias,
        on_change=on_change, **kwargs,
    )


def Text(text: str, icon: str = "", accent: bool = False, red: bool = False,
         link_alias: str = "",
         on_click: Optional[Callable[[Any], None]] = None,
         on_long_click: Optional[Callable[[Any], None]] = None,
         create_sub_fragment: Optional[Callable[[], list]] = None,
         **kwargs) -> SettingItem:
    """Plain clickable row. Use for action buttons and nested-screen entries."""
    return SettingItem(
        type=KIND_TEXT, title=text, icon=icon, accent=accent, red=red,
        link_alias=link_alias, on_click=on_click, on_long_click=on_long_click,
        create_sub_fragment=create_sub_fragment, **kwargs,
    )


def Divider(text: str = "", **kwargs) -> SettingItem:
    """Footer / divider with optional caption text."""
    return SettingItem(type=KIND_DIVIDER, title=text, **kwargs)


def Slider(key: str, text: str, default: float = 0.0,
           min_value: float = 0.0, max_value: float = 100.0,
           icon: str = "", link_alias: str = "",
           on_change: Optional[Callable[[Any], None]] = None,
           **kwargs) -> SettingItem:
    """Numeric slider."""
    return SettingItem(
        type=KIND_SLIDER, key=key, title=text, default=default,
        min_value=min_value, max_value=max_value,
        icon=icon, link_alias=link_alias, on_change=on_change, **kwargs,
    )


# ---------------------------------------------------------------------------
# Container — exposes serialisation for the Swift bridge
# ---------------------------------------------------------------------------

class PluginSettings:
    """
    Top-level settings container. Plugins typically use either:

        __settings__ = PluginSettings([Header("..."), Switch(...)])

    or, more commonly on iOS, override `create_settings(self)` on the
    BasePlugin subclass and return a list. Both forms result in a list of
    SettingItem instances handed to the Swift renderer.
    """

    def __init__(self, items: List[SettingItem]):
        self.items = list(items)

    def to_dict(self) -> dict:
        return {"items": [item.to_dict() for item in self.items]}
