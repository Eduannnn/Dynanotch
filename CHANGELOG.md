# Changelog

## 2.1.0 (build 65)

- Fixed a playback-state race where a stale read could briefly undo a pause in the notch. Play and pause now send explicit commands and refresh state after the command completes.
- Fine volume steps stay aligned to quarter steps even when the output device rounds the reported volume. Four fine decreases from one regular step now reach zero.

- AirPods battery details expand in place from the compact satellite. Case, left, and right readings use model-specific symbols and individual animated rings. Single-battery headphones use a one-item layout, and unavailable readings have a neutral state.
- The compact AirPods ring prefers the system-reported combined reading, then the lowest available earbud reading, then the single headphone reading. The case is excluded. Physical-device behavior still needs verification.
- Music stays in the center while AirPods and charging notices occupy independent satellites. Volume can slide into its own trailing pill while another satellite is occupied; the volume overlay marks mute and volume down reaches zero.
- Added Apple Music favorites and an AirPlay output picker. Refined the expanded player spacing, artwork flip, shadow, title marquee, and content clipping during collapse.
- The waveform uses live system audio and an adaptive shared peak reference. Track metadata can update while artwork loads, and artwork-derived accents ease between colors.
- Added per-model AirPods previews, including Max colors, missing readings, and separate sample readings for each component.

## Earlier 2.1.0 development notes

- Reduced bubble artwork to 20 points within its 34-point circle. Track changes now flip the persistent cover in place in collapsed and expanded presentations, without automatic track-change peeks.

- Added fast (150 ms) paused-artwork shrink/dim and waveform settling, visually checked with preview media and recorded audio levels.
- Removed the Wi-Fi/battery indicator. New foreground notices move ongoing media into a clickable left bubble; media and timers can displace each other and return through that bubble. Owned-model handoff checks pass.
- Added lock-screen window configuration through AppKit, with compact presentation, click-through behavior and disabled hardware-key filtering while locked. Physical lock/unlock validation is pending.

- Fixed pause-to-play pre-transition stretching by using a constant symbol font and fixed drawing area instead of resizable aspect-fit images. Both Magic Replace directions were visually checked.
- Reworked the spectrum response for distinct band heights: more peak headroom, less filter overlap, and relative measured band energy while preserving overall loudness and the −60 dB quiet floor. Thirty tests pass, including simultaneous strong/weak tones.

- Fixed native skip animation warm-up: initialize the resting pose before display and adopt the current trigger on view creation. Verified first-tap animation in both directions and after view recreation.

- Next/previous buttons now read the installed NowPlayingUI four-state animation, keeping native vector shapes and spring transitions. Verified both directions, rapid taps, state wrap and Reduce Motion in the hardened app; no system resource changes.

- Softened waveform peaks with gentle compression while preserving the −60 dB floor and low-level responsiveness; all 29 tests pass.
- AirPods connection previews last 10 seconds and can be requested with `--preview-airpods`; the normal connection-notice duration is unchanged.

- Added 12-point soft clipping fades to both ends of scrolling titles and artist names. They dissolve over 220 ms during reading pauses; fitting text and Reduce Motion remain unfaded.

- Replaced the permanently bright rim with dark charcoal. Both the Liquid Glass reflection and brighter stroke are localized and gated by pointer proximity; moving reflection intensity remains 10% softer. Reduce Motion no longer forces a permanent bright spot.
- Added a passive 100-point pointer-proximity response for the notch highlight and an independent 80-point response for the status bubble; click/hover hit regions are unchanged.
- Replaced frequent RGB-bin selection with saturation-aware hue groups, verified against the supplied yellow, School Days and blue/black artwork. Image sampling now uses a small sRGB bitmap instead of serializing full TIFF representations.

- Fixed Helium browser detection (`net.imput.helium.helper`), which was previously excluded by the supported-browser list.

- Black surface with an open Liquid Glass edge outline: side highlights reach the screen edge without a horizontal top stroke. The separate status bubble shares this material.
- Centered compact album artwork and browser icons within the leading wing.
- Kept a single cover-derived waveform tint.
- Magic Replace for the play/pause symbol.
- Volume changes retain the cover while playback is active; an expanded player stays expanded.
- Added public Core Audio browser-output detection. Browser cards show the app icon and live audio; this adapter does not expose website song metadata or controls.

- Removed simulated waveform motion. Audio bars are driven only by captured PCM, with stereo-aware musical-band filtering and silence gating.
- Resized bars to 2.2 points wide and up to 25 points high; widened the trailing compact wing to 38 points for 6-point horizontal insets.
- Extended collapsed surfaces 2 points below the camera obstruction to reveal the lower highlight, preserving content positions and keeping the top edge unhighlighted.
- Added a native Liquid Glass edge treatment, with a subtle darker rim.
- Added the expanded album-cover turnover and latest-track coalescing.
- Removed the in-notch Music/Timer tabs, timer setup and collapse arrow. Timer creation is in Settings; ongoing activities appear automatically.
- Corrected compact timer alignment around the physical camera.

Live pointer verification observed changing notch and bubble lighting with `pointerInteractive=false` on both sides of the collapsed notch. Captures and 56 samples are under `Build/EdgeProximityLive/`. The running Music scene also showed the corrected School Days tint.

Visual checks rendered the actual marquee at its start pause, while scrolling and at its end pause (`Build/MarqueeFadeCheck/`). The actual shared rim was captured with zero and near-pointer strengths (`Build/CharcoalRimCheck/`), confirming the charcoal resting edge and localized reflection.

Current validation: 28 tests pass, including pale-background, yellow/blue, blue/black, monochrome-noise and outside-body proximity regressions. The actual app timer/volume/animation verification also passes. Supplied artwork samples produced primary RGB values yellow `(0.817, 0.782, 0.212)`, School Days `(0.475, 0.469, 0.817)`, and blue/black `(0.287, 0.592, 0.915)`; local artifacts are under `Build/ArtworkFixtures/`.

Live Helium verification: the running installed app identified `Helium` with `browserAudio=true`, received nonzero PCM, and produced different measured and displayed band levels across four consecutive samples. The compact Helium icon and six bars were captured on the built-in display. Local evidence: `Build/helium-live-verified.json` and `Build/helium-live-visible.png`.

# 2.0.0 — A New Leaf

- Added app-owned timers with minute/second presets, pause/resume, expiry, repeat, cancellation, relaunch recovery and permission-aware background notifications.
- Added Music/Timer switching and click-to-pin expansion, with Escape/up-arrow collapse.
- Replaced competing chrome animations with a display-linked spring coordinator. Width, height, offset, corners and the persistent artwork share one trajectory; reversal retains velocity and the link stops at rest.
- Removed the permanent pointer-polling timer. Mouse events and actual animated geometry drive the interactive region, excluding the physical camera and rounded transparent corners.
- Moved expanded content below the camera and corrected timer setup clipping.
- Added a playback indicator when audio analysis is off, with a clear distinction from an actual audio waveform. Reduce Motion stops decorative motion.
- Bounded artwork downloads and Apple events; made partial track metadata more tolerant and play/pause react immediately with rollback on errors.
- Fixed service teardown, added the source files to the Xcode project and aligned local signing with the public Automation entitlement.

## Validation

20 automated tests pass. The actual app verification passed timer pause/expiry/repeat/cancel and display-linked interruption/settling. Expanded/compact media and timer setup/running/paused/finished screens were rendered and inspected. The installed 2.0.0 app was launched and its timer panel captured on the physical 1710 × 1112 display.

The lifecycle/rendering verification uses explicitly labeled preview media and isolated timer storage. It does not certify live Music/Spotify commands, Bluetooth connections or background notification delivery. macOS permission prompts must be resolved normally. Other apps' native Live Activities are not automatically received; general browser metadata is not implemented.

The prior source and installed application are retained under `Backups/`. Build outputs and local verification artifacts are under `Build/`; neither is intended for public source commits.
