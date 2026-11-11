# Stable signing

Dynanotch uses the local Apple Development certificate and retains bundle identifier `com.eduannnn.quickshell-notch.mac`. The build script reads `.signing-identity`, checks that it is valid, and refuses ad-hoc fallback. For direct Xcode builds, create the ignored `Signing.local.xcconfig` next to `Signing.xcconfig` with `DEVELOPMENT_TEAM = YOUR_TEAM_ID` and `CODE_SIGN_IDENTITY = YOUR_CERTIFICATE_FINGERPRINT`. Both Debug and Release read that local configuration. Keep the same identity as the build script. The private key stays in the login Keychain.

Validation on 2026-11-10 signed two app copies with different bundle versions. Both passed strict signature verification, had different code hashes, and shared exactly the same certificate-based designated requirement. Results: `Build/SigningValidation/result.json`. The changed copy is a validation artifact, not the installed app.

Moving from an ad-hoc identity to this certificate may require granting permissions once more. Future builds signed with the same identity should retain identity-based permission grants; actual retention remains to be observed across updates. Changing certificate, bundle identifier, install location, or OS policy can still affect permissions.

The certificate expires in November 2027. Renew signing before it expires and re-check identity compatibility; do not silently fall back to ad-hoc signing. This is local development signing, not a notarized distribution setup.
