# ScrollSplit

A native macOS menu bar app with separate vertical scroll reversal for mouse wheels and trackpads. Built for Apple silicon, macOS 13 or later.

## Requirements

There are no third-party dependencies. The app uses macOS's AppKit, SwiftUI, ApplicationServices/Core Graphics, and ServiceManagement frameworks. Building requires Apple's Command Line Tools and Swift compiler. Running requires Accessibility permission.

## Build from source

```sh
git clone https://github.com/neysofu/scrollsplit.git
cd scrollsplit
./build.command
```

The build creates **ScrollSplit.app** in the repository directory. Follow the setup steps below before testing scrolling in other apps.

## Start

1. Move **ScrollSplit.app** to Applications, then double-click it. Move it before granting access or enabling login launch so macOS remembers its final location.
2. Click the up/down arrow icon in the menu bar.
3. Click **Grant Accessibility Access**. In System Settings → Privacy & Security → Accessibility, enable ScrollSplit. If it is missing, click **+** and select the app.
4. Leave **Mouse** on and **Trackpad** off to reverse your mouse wheel while keeping your current trackpad direction. Adjust either switch to taste.
5. Optionally enable **Open at login**.

The app connects automatically after access is granted. Its switches reverse scrolling relative to your current macOS setting; changing that system setting changes the baseline for both devices. Horizontal scroll values, gesture phases, and momentum phases are preserved. **Enable ScrollSplit** pauses or resumes the adjustment. Quitting restores ordinary scrolling immediately.

## Device detection

ScrollSplit treats line-based scroll events as mouse wheels and continuous events as trackpad/smooth scrolling. The panel shows the last detected type. Magic Mouse and some mouse drivers emit continuous events, so they can use the Trackpad switch too. This version cannot separate two devices that emit the same type of event. If that happens with your mouse, disable its driver's smooth scrolling if available, or use a utility with hardware-specific device detection. Avoid running multiple scroll-reversal utilities together.

## Privacy and permissions

The app filters only scroll-wheel events. It has no network code, telemetry, keyboard monitoring, or event logging. Preferences are saved locally using macOS UserDefaults. Accessibility access is needed to modify scrolling in other apps.

This is a locally built, ad-hoc signed app, not an Apple-notarized distribution. Rebuilding changes its code signature; macOS may require removing and adding its Accessibility entry again. If scrolling does not change after granting access, quit and reopen the app and check the permission switch.

If System Settings shows access enabled but ScrollSplit still says **Accessibility access needed**, remove its entry from the permission list, add the current app from Applications, and enable access again. The panel must show **Active** before it can modify scrolling.

## Build and verify

The source is in **Source/main.swift**. Run **build.command** with Apple's Command Line Tools installed. It builds the app, signs it locally, and runs 48 synthetic event cases covering device selection, both directions, pause, and preservation of horizontal values, phases, and modifiers. You can rerun those checks with:

```sh
./ScrollSplit.app/Contents/MacOS/ScrollSplit --self-test
```

The event model follows Apple's [continuous scrolling field](https://developer.apple.com/documentation/coregraphics/cgeventfield/scrollwheeleventiscontinuous) and [scroll delta fields](https://developer.apple.com/documentation/coregraphics/cgeventfield).

## Remove

Turn off **Open at login**, quit ScrollSplit, and move the app to Trash. You can remove its Accessibility entry in System Settings.
