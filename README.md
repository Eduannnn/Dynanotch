# Dynanotch

**Version 1.0.0 · First stable release**

A SwiftUI and AppKit app that turns the MacBook camera notch into an interactive spot for media, device battery information, and system controls. Dynanotch draws its own interface. It runs without patches to macOS or changes to SIP.

![Expanded player showing sample track artwork, a progress bar, and playback controls](docs/images/player.jpg)

## What it does

- **Now playing.** Expand the notch to see artwork, scrolling track information, a seek bar, and playback controls for Music and Spotify. Music also supports favorites and AirPlay output selection. Track changes flip the cover in place, and the waveform and progress bar take their accent from the artwork.
- **Audio from other apps.** Browser and other supported app audio can show an app icon and live waveform. Dynanotch does not read individual browser tabs for track metadata or playback controls.
- **AirPods.** Connection notices use the pairing animation available on your Mac and show the reported listening battery level. Click the left AirPods satellite to expand the same pill and see separate case, left, and right readings. Headphones such as AirPods Max show a single reading. Missing readings stay unavailable.
- **Charging and volume.** Charging and volume can use their own trailing pill when the main notch is occupied. Volume changes during playback keep the artwork visible; an × marks mute.
- **Timers.** Start a Dynanotch timer from Settings → Activities. These timers are separate from Clock. Dynanotch does not import other apps’ Live Activities.

## Build and run

Use a Mac with macOS 14.4 or later, Xcode with Swift 6, and a valid Apple Development or Developer ID Application signing identity in Keychain. The current build was tested on Apple Silicon. Liquid Glass requires macOS 26 or later.

```sh
./Scripts/build-app.sh
open Build/Dynanotch.app
```

The script builds a release app and verifies its signature. If you have several valid certificates, set `DYNANOTCH_SIGNING_IDENTITY` to the installed identity’s fingerprint or put the fingerprint in the ignored `.signing-identity` file. For direct Xcode builds, see [stable signing](docs/stable-signing.md). The build is for local use and is not notarized.

For everyday use, keep a single copy in Applications. Quit the running app before replacing it. Keep its bundle identifier and signing identity stable between updates to help macOS retain permission grants.

## Use the notch

- Hover over an active compact notch to expand it temporarily. Click to pin it open; press Escape or click outside to collapse.
- Open Settings from the menu-bar icon or by reopening Dynanotch from Applications. With Accessibility enabled, press **⌘,** while the pointer is over the notch.
- In General settings, preview AirPods notices by model, choose a Max color, and simulate missing battery information. Preview readings are sample values and do not connect a device.

| macOS permission | Used for |
| --- | --- |
| Automation | Reading and controlling Music or Spotify when you use that player |
| System audio recording | Measuring live audio for the waveform; no microphone input or recordings written to disk |
| Accessibility | The notch Settings shortcut and optional replacement for the volume and brightness overlays |
| Notifications | Optional alerts for Dynanotch timers |

Quit Dynanotch before removing or re-granting Accessibility. See the [input incident notes](docs/incident-2026-11-10.md) for the confirmed findings and remaining uncertainty.

## Development

```sh
xcrun swift test
./Scripts/build-app.sh
Build/Dynanotch.app/Contents/MacOS/Dynanotch --verify-app Build/Verification
```

`NotchCore` holds the shared activity, input, and audio logic. `NotchMac` handles windows, SwiftUI, and macOS integrations. The app verifier uses synthetic activities and battery readings. Live Bluetooth readings, lock-screen visibility, and routing audio to a physical AirPlay receiver still need broader hardware testing. Optional system adapters vary by macOS release. Apple pairing movies and skip animations are read from the installed OS when available; they are not distributed here.

See the [changelog](CHANGELOG.md), [porting notes](PORTING.md), and [implementation notes](docs/). Dynanotch began as a Swift port of [Eduannnn/quickshell-notch](https://github.com/Eduannnn/quickshell-notch) at commit `85505dcd789589a61cc981115b892d6475e11ada`.

## License

Dynanotch is licensed under the [GNU General Public License v3.0](LICENSE).
