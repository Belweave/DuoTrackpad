# Set up Duo Trackpad

You need an Apple Silicon Mac with macOS 14 or later, the Duo Trackpad iPhone beta, and a network that lets the two devices talk to each other.

## Install the Mac receiver

Download the DMG from [GitHub Releases](https://github.com/Belweave/DuoTrackpad/releases). Open it, drag **Duo Receiver** to **Applications**, and open the app from there. Eject the disk image afterward.

In System Settings → Privacy & Security, allow:

- **Accessibility:** lets Duo Receiver move the pointer, click, scroll, and use Mac controls. Some macOS versions call this **Device Control and Data Access**.
- **Local Network:** lets your iPhone discover and connect to the receiver.

The status changes to **Ready to control your Mac** after access is enabled. macOS controls these permissions; the app cannot grant them itself.

## Pair your iPhone

1. Open Duo Trackpad. Tap the surface to open connection settings.
2. Select your Mac and enter its eight-digit code.
3. Close settings and slide a finger to move the pointer.

The apps save their pairing in the device’s Keychain. Keep the receiver running; closing its window leaves its menu-bar control available. Quitting the app stops receiving.

## Reconnect or change Mac

Open the iPhone app to reconnect automatically. A four-finger tap opens settings. **Disconnect** stops the connection. **Forget** removes trust and requires pairing again. The Mac menu bar can pause receiving or forget paired devices.

## If your Mac does not appear

- Confirm both devices are on the same local network. Guest networks may isolate devices.
- Allow incoming connections to Duo Receiver if macOS Firewall asks.
- On the phone, choose **Connect by IP address** and enter the address shown by the receiver. It uses TCP port **48571**.
- Keep the phone app in the foreground. Returning from the background reconnects.

For a simulator on the same Mac, use **127.0.0.1**. Do not use that address on a physical iPhone.

## If connected input does nothing

Check Accessibility. If an older development build’s entry looks enabled but is not working, remove the stale entry and add the installed copy from **Applications**. macOS may require local authentication. Never send a password to the app or an issue report.

## Update or uninstall

Quit the receiver, replace it in **Applications** with the new DMG, and reopen it. Pairing should survive updates with the same bundle and Keychain identity. Moving from a development certificate to the first Developer ID release may require granting Accessibility again.

To uninstall, quit and move the app to Trash. Use **Forget paired devices** first to revoke remembered devices. Deleting the app alone does not delete Keychain items.
