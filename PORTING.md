# Porting notes

These notes record the original port and historical releases. See the [README](README.md) for current behavior.

Upstream: `Eduannnn/quickshell-notch`, supplied ZIP, commit `85505dcd789589a61cc981115b892d6475e11ada`.

## Geometry preserved from the QML

The native views use the upstream `uiScale = 0.58`, 14 pt player inset, 2 pt cutout safety padding, six bars, 3.5 second track peek, 150 ms hover-collapse delay, 4 second notices, and 1.5 second OSD. These are logical points, corresponding to the original output-logical coordinates. The actual camera width/height comes from the Mac's display rather than the Linux calibration file. Version 1.5 updates spring timing and expanded transport glyphs in response to the user's reference; it retains the panel's geometry.

| Element | Native baseline copied from upstream |
| --- | --- |
| Expanded player | `688 × 0.58 = 399.04` pt wide; `334 × 0.58` pt content height plus the calibrated safe top offset |
| Track peek | `max(cameraWidth + 80, 399.04 × 0.94)` pt wide; camera height + 56 pt including safety offset |
| Collapsed media | Camera height; 38 pt artwork wing and 49 pt waveform wing with 2 pt safety padding |
| Artwork | 28 pt collapsed, 40 pt peek, `112 × 0.58 = 64.96` pt expanded |
| Corners | 12 pt collapsed, 24 pt peek, `70 × 0.58 = 40.6` pt expanded |
| Connection indicator | 50 pt attached slot; 34 pt detached bubble with 8 pt gap |
| Device/power/OSD | Camera height throughout; left/right wings sized around the cutout rather than an expanded toast |

Version 1.1 removes the visible percentage from the volume/brightness wings as requested. The 55 pt gauge stays the same size; the trailing wing shrinks to the gauge plus its original padding. Battery and device layouts keep their existing geometry.

| Upstream | Native implementation | Behavior |
| --- | --- | --- |
| Wayland panel | Borderless nonactivating NSPanel + SwiftUI | Anchored to the selected screen's top edge; joins Spaces and full-screen desktops |
| Calibration JSON | NSScreen safe area/auxiliary areas + UserDefaults | Automatic cutout dimensions with optional manual width/height/offset; no Linux calibration file is reused |
| MotionSpring / MotionContent | SwiftUI spring and content transitions | Shape and content retarget smoothly; respects Reduce Motion |
| Resting player | Artwork/camera/waveform in one row | Stays at the physical cutout height |
| Track peek | Temporary compact metadata row | Approximately 3.5 seconds on new content; distinct from the resting player |
| Expanded player | SwiftUI player on hover | Album art, two metadata lines, elapsed/remaining time, seek, previous/play/next |
| MediaIdentity.js | TrackIdentity | Stable player/track IDs avoid reannouncing partial metadata changes |
| MPRIS | Music and Spotify Apple Events | Native app integration; no global browser metadata feed |
| CAVA + PipeWire | Optional Core Audio process tap | Six live spectrum bands, matching the original bar count; no microphone or audio files |
| Album color extraction | One-time artwork palette sampling | Dark colors are lifted for readability against black |
| ConnectionIndicator | SF Symbol + open battery arc | Network state and real computer battery level; detached beside active media/notices |
| BluetoothNotifications | IOBluetooth paired-device snapshots | Bounded, deduplicated connection/disconnection queue; SF Symbols; collapsed inline wing |
| UsbNotifications / udev | IOKit USB registry snapshots | External USB add/remove notices with device name in hover/accessibility; collapsed inline wing |
| PowerNotifications / UPower | IOKit power sources | Plug-in charging notice, live battery update, 20%/5% warnings; collapsed inline text/battery wings |
| SystemOsd / PipeWire | Core Audio + hardware-key filter | Successful volume/mute keys are consumed and applied directly, suppressing macOS's HUD; an SF Symbol and gauge appear for 1.5 seconds |
| SystemOsd / brightnessctl | Optional DisplayServices bridge | Actual supported built-in display brightness; disabled gracefully if unavailable |
| nmcli networks/passwords | Native Wi-Fi Settings | Direct Wi-Fi power toggle; network authentication handled by macOS |
| hypridle pause | IOPM power assertion | Prevents idle display/system sleep until disabled or the app quits |
| systemctl power actions | System Events | User-selected sleep/restart/shutdown; restart/shutdown confirm before proceeding |
| SF symbol exporter | Image(systemName:) / NSImage(systemSymbolName:) | Uses the OS symbol catalog directly; no exported or bundled Apple font files |

## Verification scope

- Debug and optimized Release builds with the installed Swift toolchain.
- Xcode project and local package resolution; native app target build.
- Thirteen XCTest cases cover queue deduplication and late battery updates, queue bounds/dismissal, OSD/notice/control priority and scrub latch, safe seek endpoints, track identity, artwork luminance, invalid battery values, system-key parsing, autorepeat, paired down/up consumption, safe fallback, capture reset, and standard/fine volume steps.
- Rendered SwiftUI previews checked for player, Control Center, inline device notices, and charging/OSD layouts.
- Live app checked through macOS accessibility: Control Center, Settings, collapsed player, expanded player, preview pause, seek increment, track change, and app quit. Native battery, network, output name, volume, and brightness reads were observed.
- The live transport/seek UI check uses the explicitly labeled preview player. An active real Music or Spotify session and their Automation consent were not available for end-to-end player verification. Device hot-plug and optional audio capture depend on the user's hardware and consent; no pairing, audio-capture permission, network change, sleep, restart, shutdown, or real volume/brightness change was performed during validation.
- Version 1.1 is checked through builds, hardware-key policy tests, rendered OSD previews, and a permission-status diagnostic. Actual HUD suppression requires the user to grant Accessibility to this app. The diagnostic does not request permission or simulate keys. The computer-use/mouse automation tools are not used for this revision.

The app is a locally ad-hoc signed Apple Silicon build. It is not notarized. All code is included; nothing was pushed to GitHub.

## Version 1.2: runtime asset references

The Control Center sliders now optionally read Apple's installed fill/disabled-fill/normal-knob/pressed-knob images, and the Bluetooth tile reads the installed SiriUI Bluetooth glyph. No asset catalog or extracted images are added to the application bundle. `--check-assets` on the installed 27.2 system verified both image sets are available, the optional track color is unavailable (using the original track color), and the SiriUI executable is not loaded. Both the system-artwork and forced-fallback Control Center previews were rendered and inspected. The original 16 pt track, 20 pt visible knob, interaction areas, and notch dimensions remain intact.

This deliberately does not bind to private island Swift function ABI or change system feature flags. The Assistant Island resource search and its limits are documented in the separate macOS 27.2 investigation report.

## Version 1.5: expanded controls and island-style motion

Larger, evenly spaced transport glyphs follow the user's screenshot. The play/pause glyph is 28 × 38 pt, skip glyphs are 39 × 22 pt, and all hit areas are 56 pt square. Springs now distinguish the shape from the more damped height/corner motion, and content enters immediately with a short fade and 2 pt slide, without blur. A fixed black camera cover protects the cutout throughout transitions. Reduced-motion behavior follows system accessibility settings. Static previews were rendered and inspected for control spacing; build verification checks the SwiftUI transition implementation. Exact private iOS timing has not been established.

Version 1.5.1 tightens shape/height spring responses to 0.20/0.22 seconds, removes the insertion delay and blur, and shortens pointer-exit grace to 150 ms.

Version 1.6 reorganizes Control Center into five matching quick-control tiles, paired Display/Sound cards and a media strip. Outer geometry and actions are unchanged. Release build passed and the updated preview was visually inspected.

Version 1.6.1 makes Focus a direct Do Not Disturb toggle through an Apple Set Focus shortcut, imported once with user approval. A live on/off round-trip passed and restored the initial off state. Focus status reads Assertions.json without modifying it; unavailable status is shown as unknown. Low Power uses fixed pmset arguments via administrator-authorized AppleScript, verifies both power profiles, handles cancellation, and prevents overlapping requests. The Low Power password flow requires a user click and was not exercised during build validation. No private DND service or database-writing workaround is shipped.

## Version 1.7: Control Center removed

All Control Center views, presentation state, entry points and preview output were removed at the user’s request. Its Focus/Low Power actions, Shortcuts resources and system-artwork adapter were removed too. No privileged helper was installed. The earlier 1.2–1.6 notes above describe historical versions. The idle gear opens Settings; media, inline device/power notices and keyboard HUD remain. Battery polling is isolated from potentially blocked Bluetooth lookups so charging notices keep updating.

## Version 1.8: direct AirPods pairing artwork

The inline AirPods glyph references installed BluetoothUIService MOV loops using AVQueuePlayer/AVPlayerLooper and a transparent AVPlayerLayer. Representative PIDs are 8194 (AirPods), 8206 (AirPods Pro), and 8202 (AirPods Max). Family selection uses the Bluetooth device name; unrelated devices and USB notices retain SF Symbols. No Apple movie is embedded. A decoded in-memory poster covers startup and reduced-motion/disconnect states. Unavailable/failed movies fall back to SF Symbols. Collapsed dimensions are unchanged.

Asset decoding and muted looping playback were verified for all three source files. AirPods Pro/Max inline previews were rendered and inspected; builds and 17 tests passed before installation. Real device reconnection was not simulated.

Version 1.8.2 retains the battery/Wi-Fi indicator at its original idle and floating positions while keeping Control Center removed. Its progress arc turns green while charging (charging takes priority) and red at <=5% when not charging; existing Low Power yellow and normal white remain. Battery and Wi-Fi polling are isolated from Bluetooth lookups so the indicator continues updating.
