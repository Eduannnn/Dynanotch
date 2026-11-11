# AirPods model and colour artwork

Dynanotch optionally reads `productID` (UInt16), `vendorID` (UInt16), and `colorID` (UInt8) from the installed IOBluetoothDevice objects. Runtime inspection on macOS 27.3 confirmed those selector return types. The adapter checks selector availability, argument count and return encoding before calling. These are undocumented, read-only getters; no scanning, private entitlement, pairing change or daemon modification is used. If unavailable, family matching by name remains a fallback. Model-specific metadata requires an Apple vendor ID.

Known product IDs were checked against local CoreBluetoothUI `Resources/AssetPaths*.plist`. Separate movies live in BluetoothUIService `Contents/Resources/Banner-PID-<product>-mov/`. The resolver tries the exact product/colour movie, then that product's default movie, then a generic family movie. It never reuses a newer generation's colour number with older artwork. Original Max colour code 0 aliases 15 (both map to B515-0-Black.icns in Apple's catalogue). USB-C Max uses 8223 with colour codes 18–22. Unavailable newer movies retain a family fallback.

Posters are cached by resolved movie URL, preventing one Max colour from reusing another's poster. Live notices receive late metadata updates without replaying connection notices. A confirmed non-Apple device retains its generic icon even if named AirPods. Reduce Motion keeps a still frame.

Verification: 35 core tests passed, including renamed-device selection, vendor rejection, colour path order, missing metadata and late updates. `--check-airpods-assets` verifies decoding of installed base, generation and colour movies.

Limit: no real AirPods connection has been tested for this change. Getter presence and fixture-based selection do not prove that macOS supplies accurate or fresh colour data for every device. Unknown/unreported colour values may map to a default; there is no inferred colour from device names or serial numbers. Apple resources stay in the system bundle and are not copied into the app.
