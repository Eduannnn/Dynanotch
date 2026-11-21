#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${NOTCH_BUILD_DIR:-$project_root/.build}"
app_path="${1:-$project_root/Build/Dynanotch.app}"
local_assets="${DYNANOTCH_BUNDLE_SYSTEM_ASSETS:-1}"
asset_path="$app_path/Contents/Resources/BundledAnimations"
target_architecture="${DYNANOTCH_BUILD_ARCH:-$(uname -m)}"
case "$target_architecture" in
    arm64|x86_64) architecture_flags=(--arch "$target_architecture") ;;
    *) echo "DYNANOTCH_BUILD_ARCH must be arm64 or x86_64." >&2; exit 1 ;;
esac
if [[ "$local_assets" != 1 && -e "$asset_path" ]]; then
    echo "Choose another output path. This app bundle contains locally copied system assets." >&2
    exit 1
fi
signing_identity="${DYNANOTCH_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" && -r "$project_root/.signing-identity" ]]; then
    signing_identity="$(<"$project_root/.signing-identity")"
fi
if [[ -z "$signing_identity" ]]; then
    signing_candidates=("${(@f)$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/awk '/Apple Development:|Developer ID Application:/ { print $2 }')}")
    signing_candidates=(${signing_candidates:#})
    if (( ${#signing_candidates} != 1 )); then
        echo "A stable signing certificate is required. Add an Apple Development certificate in Xcode → Settings → Accounts → Manage Certificates, or select an installed certificate with DYNANOTCH_SIGNING_IDENTITY (its 40-character fingerprint)." >&2
        exit 1
    fi
    signing_identity="$signing_candidates[1]"
fi
if [[ ${#signing_identity} != 40 || "$signing_identity" == *[^[:xdigit:]]* ]]; then
    echo "DYNANOTCH_SIGNING_IDENTITY must be an installed certificate's 40-character fingerprint. Ad-hoc signing is disabled." >&2
    exit 1
fi
if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/awk -v wanted="$signing_identity" '$2 == wanted { found = 1 } END { exit !found }'; then
    echo "The selected signing identity is not currently valid. Signing stopped; ad-hoc fallback is disabled." >&2
    exit 1
fi
sdk_version="$(xcrun --show-sdk-version)"
linker_flags=(-Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$sdk_version")
xcrun swift build --package-path "$project_root" --scratch-path "$build_dir" --configuration release "${architecture_flags[@]}" "${linker_flags[@]}"
bin_dir="$(xcrun swift build --package-path "$project_root" --scratch-path "$build_dir" --configuration release "${architecture_flags[@]}" --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/Dynanotch" "$app_path/Contents/MacOS/Dynanotch"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
if [[ -d "$project_root/Resources/Themes" ]]; then
    /usr/bin/ditto "$project_root/Resources/Themes" "$app_path/Contents/Resources/Themes"
fi
if [[ -f "$project_root/Resources/AppIcon.icns" ]]; then
    cp "$project_root/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
fi
if [[ "$local_assets" == 1 ]]; then
    pairing_root="/System/Library/CoreServices/BluetoothUIService.app/Contents/Resources"
    skip_archive="/System/Library/PrivateFrameworks/NowPlayingUI.framework/Resources/ForwardBackward.caar"
    mkdir -p "$asset_path"
    # Include color variants for the AirPods models recognized by Dynanotch.
    for product_id in 8194 8202 8206 8207 8211 8212 8217 8223 8228 8229 8230 8231 8237 8240 8242 8246 8247; do
        banner="Banner-PID-${product_id}-mov"
        for movie in "$pairing_root/$banner/"*.mov(N); do
            mkdir -p "$asset_path/$banner"
            /bin/cat "$movie" > "$asset_path/$banner/${movie:t}"
        done
    done
    if [[ -r "$skip_archive" ]]; then /bin/cat "$skip_archive" > "$asset_path/ForwardBackward.caar"; fi
fi
/usr/bin/codesign --force --sign "$signing_identity" --options runtime \
    --entitlements "$project_root/Resources/Dynanotch.entitlements" \
    --identifier com.eduannnn.quickshell-notch.mac "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
echo "Built: $app_path"
