# Gestures and controls

| Gesture | Result |
| --- | --- |
| Slide one finger | Move the pointer |
| Tap one finger | Click; repeated taps can double-click |
| Double-tap and hold, or hold for 0.38 seconds | Drag; lift to release |
| Tap two fingers | Right-click; waits up to 280 ms for a second tap |
| Slide two fingers | Horizontal and vertical scrolling with momentum |
| Pinch two fingers | Zoom using Command + / − |
| Double-tap two fingers | Reset zoom using Command 0 |
| Rotate two fingers | Choose an exposed Rotate Left/Right menu command |
| Tap three fingers | Look up using Control Command D |
| Swipe three or four fingers up / down | Mission Control / App Exposé |
| Swipe three or four fingers sideways | Switch desktop or full-screen Space |
| Spread / pinch four fingers | Show Desktop / Apps |
| Swipe left with two fingers from the right edge | Open Notification Center |
| Tap four fingers | Open connection, feel settings, and Mac controls |

**Three-finger drag** replaces three-finger swipe and lookup gestures. Four-finger gestures remain available.

Settings include pointer speed, acceleration, scroll speed, natural scrolling, and click haptics. VoiceOver has a custom action to open settings. Mac controls also have buttons in the connection sheet.

## Limits

Duo sends mouse events, keyboard shortcuts, and accessible menu commands. It does not emulate Apple’s multitouch trackpad hardware.

- Zoom depends on the foreground app’s shortcuts. Command 0 resets zoom; it is not native Smart Zoom.
- Rotation is discrete and needs exposed English Rotate Left/Right menu items.
- Mission Control and desktop switching follow the Mac’s configured shortcuts.
- Notification Center needs an accessible menu-bar control.
- Force Click, pressure sensing, universal native magnify/rotate events, and physical trackpad haptics are not supported.
