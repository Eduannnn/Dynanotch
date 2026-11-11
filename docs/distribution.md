# Distribution packaging

For the precompiled download, use a **Developer ID Application** signing identity from an Apple Developer Program team. The Apple Development identity used for local builds is a different certificate. Publish the Apple Silicon ZIP only after notarization succeeds and the extracted app passes Gatekeeper assessment.

1. Build with `./Scripts/build-app.sh` and copy `Build/Dynanotch.app` to a separate staging folder.
2. Sign the staged app with the Developer ID Application identity, Hardened Runtime, a secure timestamp, and `Resources/Dynanotch.entitlements`.
3. Package that app as a ZIP with `ditto -c -k --keepParent` and submit the ZIP with Xcode’s `notarytool`. Use a locally configured Keychain profile for authentication.
4. After Apple accepts it, run `xcrun stapler staple` and `xcrun stapler validate` against the staged **app**. Create the final ZIP from the stapled app; ZIP files cannot be stapled directly.
5. Extract the final ZIP and check the app with `codesign --verify --strict` and `spctl --assess --type execute --verbose=4`. Test a fresh download on another supported Mac before publishing. Attach the ZIP and its SHA-256 checksum to the matching GitHub release.

See Apple’s [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) and [packaging guide](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution). Do not store certificates, private keys, or notary credentials in the repository.
