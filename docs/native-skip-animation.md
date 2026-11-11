# Native next/previous animation

The expanded player reads `/System/Library/PrivateFrameworks/NowPlayingUI.framework/Resources/ForwardBackward.caar`. The asset stays installed in macOS; Dynanotch does not copy or modify it. It is a keyed Core Animation archive, with four arrow groups, four states and original spring transitions.

Targeted read-only inspection used `dyld_info` against the NowPlayingUI image in the shared cache, plus property-list inspection and an owned-process loader. No Apple process was attached to or modified.

Evidence on macOS 27.3 (26C5035r), NowPlayingUI UUID `B3A10FE6-6476-335A-BB47-D52964E39158`:

- `Asset.previous` getter: `0x2A0686EBC`; its once initializer begins at `0x2A0686E00`.
- `Asset.next` getter: `0x2A0687014`; its initializer at `0x2A0686F5C` stores `forward.fill`.
- The next initializer at `0x2A06894A0` passes direction `1` to the shared builder `0x2A068AA40`; previous passes `0`. The shared builder constructs `State 1` through `State 4`, with 0.8-valued timing entries, and inverts direction at `0x2A068ABF0`.
- The installed archive has matching four states, layer names `ffwd0 shape` through `ffwd3 shape`, original vector arrow paths and spring transitions. Runtime loading confirms an 84 × 84 root layer.

`NativeSkipGlyph.swift` uses optional, runtime-checked private QuartzCore `CAPackage` and `CAStateController` interfaces in Dynanotch's own process. Each click advances the packaged states, and previous mirrors the layer tree. Layout fits the actual vector ink, so direction and centering remain consistent. The SwiftUI button still sends one existing playback command. Play/pause Magic Replace remains separate. It uses a constant symbol font and fixed drawing area to avoid pre-transition aspect-fit stretching; both directions were captured in `Build/PlayPauseCanvasCheck/`.

These are private interfaces and may change with macOS; when the resource or expected API/state structure is absent, the view displays the original static SF Symbol. Static image export also uses that fallback. Reduce Motion suppresses tap animation.

## Verification

`Dynanotch --verify-native-skips Build/NativeTransport` runs without starting device/media services. It verifies original-resource loading in the hardened app, active Core Animation tracks, rapid taps, `State 2 → 3 → 4 → 1 → 2`, and reduced-motion behavior. Both mirrored directions and intermediate/settled frames were captured and inspected. The user confirmed that this is the requested animation. The verification sends no media commands.

The actual control rendering and playback behavior after installation remain separate from this isolated animation check. Current local logs and images are in `Build/NativeTransport/`.

Resource SHA-256: `1e134b98de045428ed7dc2307f48452d9ba3618f88ad69c5cdb40c6f4e866097`.

## First-click reliability correction

The first implementation started without an explicit package state. Its first click selected `State 1`, the resting pose, moving the common visible arrow by only two native units. It did not perform a normal skip. The earlier test only checked that at least one tap animated and missed this case.

The package now applies `State 1` without animation before display and removes setup animation tracks. The first user click goes to `State 2`. A newly created NSView also adopts its incoming SwiftUI trigger value, preventing a stale click from replaying when the player is recreated.

The strengthened hardened-app check passes initial priming, active animation tracks on every tap, more than 20 native units of travel for a visible arrow on every tap, both directions, rapid taps, state wrap, Reduce Motion, and a recreated view receiving a nonzero trigger. Captures and results are in `Build/NativeTransportFirstClick/`. No SwiftUI replacement of Apple's animation was needed.
