# Activity handoff and lock-screen display

Notices and foreground activities can displace ongoing media/timers into one leading bubble. The existing persistent artwork view moves to its bubble position through the surface spring; it is not duplicated. Clicking the bubble dismisses transient overlays and expands that activity. The former Wi-Fi/battery indicator is removed.

`Build/ActivityHandoffCheck/` contains successful owned-model checks and renders for notice → media bubble → restored player, timer/media handoff, compact lock-state selection and restored expansion after unlock. Pause shrink/dim and a 150 ms waveform settle were separately captured in `Build/PausedArtworkCheck/` and `Build/WaveformSettleCheck/`; the waveform rendering test used recorded measured levels, not live playback.

Lock-screen configuration uses public `NSWindow.canBecomeVisibleWithoutLogin` (declared in the installed AppKit NSWindow.h) and a screen-saver window level while the normal lock notification is active. The panel is noninteractive while locked; it does not become key, open settings, expand or filter hardware keys. Normal window level and interaction return on unlock. The setting can be disabled in General Settings.

No lock or authentication UI is replaced, no security setting is changed, and no service is installed. This applies while the logged-in user's Dynanotch process is running; no preboot/login host is added.

Actual visibility on this machine's lock screen remains unverified until the user performs a lock/unlock check. HUD diagnostics record the event count and last locked window level to distinguish notification/configuration success from visually confirmed display.
