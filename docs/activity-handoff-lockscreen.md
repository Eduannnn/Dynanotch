# Activity handoff and lock-screen display

Device notices can move Now Playing into a leading bubble. The album artwork moves with the surface spring. Clicking the bubble dismisses the notice and expands the player.

`Build/ActivityHandoffCheck/` contains checks for a device notice moving media into a bubble, restoring the player, and collapsing and restoring the layout across a simulated lock and unlock. The waveform rendering check in `Build/WaveformSettleCheck/` used recorded audio levels.

Lock-screen configuration uses public `NSWindow.canBecomeVisibleWithoutLogin` (declared in the installed AppKit NSWindow.h) and a screen-saver window level while the normal lock notification is active. The panel is noninteractive while locked; it does not become key, open settings, expand or filter hardware keys. Normal window level and interaction return on unlock. The setting can be disabled in General Settings.

No lock or authentication UI is replaced, no security setting is changed, and no service is installed. This applies while the logged-in user's Dynanotch process is running; no preboot/login host is added.

Actual visibility on this machine's lock screen remains unverified until the user performs a lock/unlock check. HUD diagnostics record the event count and last locked window level to distinguish notification/configuration success from visually confirmed display.
