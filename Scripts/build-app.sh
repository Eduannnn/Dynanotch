#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${NOTCH_BUILD_DIR:-$project_root/.build}"
app_path="${1:-$project_root/Build/Dynanotch.app}"
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
xcrun swift build --package-path "$project_root" --scratch-path "$build_dir" --configuration release
bin_dir="$(xcrun swift build --package-path "$project_root" --scratch-path "$build_dir" --configuration release --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/Dynanotch" "$app_path/Contents/MacOS/Dynanotch"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
if [[ -f "$project_root/Resources/AppIcon.icns" ]]; then
    cp "$project_root/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
fi
/usr/bin/codesign --force --sign "$signing_identity" --options runtime \
    --entitlements "$project_root/Resources/Dynanotch.entitlements" \
    --identifier com.eduannnn.quickshell-notch.mac "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
echo "Built: $app_path"
