# Media refresh and accent transitions

The former serial path waited up to 1.2 seconds for polling and fetched artwork before publishing metadata. Music artwork retrieval also lacked an explicit timeout.

The new path listens for Music/Spotify playback notifications, coalesces notifications received during reads, and uses a 0.5-second fallback poll. It prioritizes the previously selected player and stops once a playing player is found. Browser inspection runs only when no dedicated player is playing.

Metadata publishes before artwork. Artwork uses a separate, two-operation queue with bounded requests; stale queued work is cancelled. Music image responses include track identity so an image cannot be applied to the wrong song. Results are also checked against the current request and snapshot. A metadata read started before an image arrived preserves the newer image on completion. Failed artwork requests retry after five seconds.

The persistent cover waits for the new image before flipping, while text updates independently. Waveform, progress and favourite accents use a 0.3-second easeInOut colour transition, respecting Reduce Motion. Colours still come from decoded cover art.

Verification: 40 tests passed and the release app built and passed strict signature verification. Live HUD diagnostics include media title, artwork readiness and playback-notification count. This does not establish an end-to-end latency bound; upstream Music/Spotify responses and artwork availability may still lag.
