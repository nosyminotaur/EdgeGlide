# Getting started with EdgeGlide

This guide shows you how to build EdgeGlide, use each gesture, and fix common
problems.

## What you need

- macOS 14 or later.
- A Mac with a trackpad, built in or external.
- Xcode or the Command Line Tools. To install the Command Line Tools, run
  `xcode-select --install`.

## Build and run

1. Clone the repository and build the app:

   ```sh
   git clone https://github.com/nosyminotaur/edgeglide.git
   cd edgeglide
   scripts/build-app.sh
   ```

2. Start the app: `open build/EdgeGlide.app`

The script writes `build/EdgeGlide.app` and signs it ad hoc.

## First launch

EdgeGlide has no Dock icon and no window. Look for the trackpad-and-hand icon
in the menu bar, and click it to open the panel.

The panel shows a drawing of your trackpad. Each zone lights up when its
gesture fires. Turned-off gestures appear dimmed. The status line says
**Ready** when everything works. Otherwise it names the most important problem
and shows a button that fixes it. The panel also has **Settings…** and
**Quit**.

## Use the gestures

- **Volume:** slide one finger up or down along the right edge.
- **Brightness:** slide one finger up or down along the left edge.
- **Mute:** double-tap the top-right corner. Make two quick taps.
- **Next or previous track:** swipe one finger left or right along the bottom
  edge.

Tips:

- Start your finger inside the edge zone. A touch that starts in the middle
  never becomes a gesture.
- Two or more fingers never trigger a gesture, so scrolling and system
  gestures keep working.
- The pointer still moves while you slide along an edge.

## Settings

To open Settings, click the menu bar icon, then click **Settings…**.

- **Gestures:** one switch for each gesture: **Volume**, **Brightness**,
  **Mute**, and **Next and previous track**.
- **Feel:**
  - **Edge width** sets how wide each edge zone is, from 5% to 25% of the
    trackpad.
  - **Sensitivity** sets how far each slide moves the level, from 0.5× to 3.0×.
  - **Strength** sets the haptic tick: **Off**, **Weak**, **Medium**, or
    **Strong**. To feel it, click **Test**.
  - **Launch at login** starts EdgeGlide when you log in.
- **About:** the version, the license, a link to the source code, and
  **Diagnostics**. Diagnostics lists the status of each feature and has
  **Refresh status** and **Rescan trackpads** buttons.

## Permissions

Trackpad input, volume, mute, brightness, and haptics need no permission.

EdgeGlide needs **Accessibility** only as a fallback for track control. It
posts media keys when the private MediaRemote framework can't send next and
previous track commands. To allow it, do one of these:

- In the panel, click **Allow media keys**.
- Add EdgeGlide in **System Settings > Privacy & Security > Accessibility**.

Each rebuild changes the ad hoc signature, so you might need to allow
Accessibility again after you rebuild.

## Launch at login

1. Move the app to `/Applications`:

   ```sh
   mv build/EdgeGlide.app /Applications/
   open /Applications/EdgeGlide.app
   ```

2. In **Settings > Feel**, turn on **Launch at login**.

If the panel says **Launch at login needs approval**, click
**Open Login Items** and allow EdgeGlide.

## Update

To get the latest version, quit EdgeGlide, then run this in the repository:

```sh
git pull
scripts/build-app.sh
open build/EdgeGlide.app
```

If you keep the app in `/Applications`, move the new build there again.

## Uninstall

1. In the panel, click **Quit**.
2. Delete `EdgeGlide.app` from `/Applications` or `build/`.
3. Optional: to delete your settings, run `defaults delete com.edgeglide.app`.

## Troubleshooting

- **No trackpad found:** open **Settings > About**, then click
  **Rescan trackpads** under **Diagnostics**. A trackpad that connects after
  launch needs a rescan. EdgeGlide rescans by itself after sleep.
- **Brightness does nothing:** brightness works only on the built-in display.
- **Volume does nothing:** some outputs, such as many HDMI and USB devices,
  have no software volume control.
- **macOS blocks a downloaded zip:** the release app is signed ad hoc, not
  notarized. To remove the quarantine flag, run
  `xattr -dr com.apple.quarantine /Applications/EdgeGlide.app`.
- **To see the logs**, run
  `log show --last 5m --info --predicate 'subsystem == "com.edgeglide.app"'`.
