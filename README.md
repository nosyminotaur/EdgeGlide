# EdgeGlide

EdgeGlide is a free, open-source macOS menu bar app that turns the edges of
your trackpad into controls:

| Gesture | Action |
|---------|--------|
| Slide one finger up or down along the right edge | Change output volume |
| Slide one finger up or down along the left edge | Change built-in display brightness |
| Double-tap the top-right corner | Toggle mute |
| Swipe one finger left or right along the bottom edge | Previous or next track |

A gesture only starts when your finger lands inside an edge zone. A touch that
starts in the middle of the trackpad is ignored, and so is any touch with two
or more fingers, so normal pointing, scrolling, and system gestures keep
working.

Each volume or brightness step plays a haptic tick, and so does every other
gesture. You can set the strength to off, weak, medium, or strong.

## Requirements

- macOS 14 or later. Developed on macOS 27.2, Apple silicon.
- Swift 6 toolchain. Command Line Tools are enough; you don't need Xcode.

## Build

1. Clone the repository and open a terminal in it.
2. To run the unit tests, run `swift test`.
3. To build the app bundle, run `scripts/build-app.sh`.

   The script builds a release binary, writes `build/EdgeGlide.app` with its
   `Info.plist`, and signs it ad hoc with `codesign --force --deep -s -`.
4. To start the app, run `open build/EdgeGlide.app`, or move it to
   `/Applications` first.

EdgeGlide has no Dock icon. Look for the hand icon in the menu bar.

## Settings

Open **Settings…** from the menu bar icon. You can change:

- **Edge width**: how far into the trackpad each edge zone reaches.
- **Sensitivity**: how far you slide for each step. At 1.0×, a full-height
  slide moves the value from 0% to 100% in 16 steps.
- One toggle per gesture.
- **Haptic strength**: off, weak, medium, or strong.
- **Launch at login**: registers the app with `SMAppService`. If macOS asks
  for approval, allow it in **System Settings > General > Login Items**.

Settings persist in `UserDefaults` under the bundle ID `com.edgeglide.app`.

The menu also shows a status line for each part: trackpad devices, volume,
brightness, media control, haptics, and launch at login. When something fails,
the menu shows the error instead of hiding it.

## Permissions

- **Trackpad input** needs no permission. EdgeGlide reads raw touches through
  the private MultitouchSupport framework.
- **Volume** and **mute** use public CoreAudio APIs on the default output
  device. Some outputs, such as many HDMI and USB devices, have no software
  volume control. The menu then reports that the device has no volume control.
- **Brightness** uses the private DisplayServices framework on the built-in
  display. External displays aren't supported.
- **Next and previous track** try the private MediaRemote framework first. If
  that fails, EdgeGlide posts the same media key events your keyboard sends.
  That fallback needs permission: choose **Allow media keys…** in the menu, or
  add EdgeGlide in **System Settings > Privacy & Security > Accessibility**.

Each time you rebuild, the ad hoc signature changes. macOS may then treat the
new build as a different app, so you might need to grant Accessibility again.

## Logs

EdgeGlide logs every failure through `os.Logger`. To see the logs, run:

```sh
log show --last 5m --info --predicate 'subsystem == "com.edgeglide.app"'
```

## Known limits

- The pointer still moves while you slide along an edge. EdgeGlide reads
  touches but doesn't block them.
- There is no on-screen volume or brightness indicator.
- Multitouch devices that connect after launch, such as a Magic Trackpad, need
  **Rescan trackpads** from the menu. EdgeGlide rescans by itself after sleep.

## Why it isn't in the App Store

EdgeGlide depends on private Apple frameworks: MultitouchSupport for raw
touches and haptics, DisplayServices for brightness, and MediaRemote for track
control. The App Store doesn't accept apps that use private frameworks, and
the app can't run in the App Sandbox. Apple can also change these frameworks
in any macOS update. EdgeGlide loads them at run time with `dlopen`, so a
missing symbol turns off one feature and shows an error, instead of stopping
the app.

## Project layout

| Path | Contents |
|------|----------|
| `Sources/EdgeGlideCore` | The gesture recognizer and other pure logic. No private frameworks |
| `Sources/EdgeGlide` | The menu bar app, touch monitor, and system controls |
| `Tests/EdgeGlideCoreTests` | Recognizer tests, written with Swift Testing |
| `scripts/build-app.sh` | Builds and signs `build/EdgeGlide.app` |

## License

EdgeGlide is available under the MIT License. See [the license file](LICENSE).
