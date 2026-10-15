#!/bin/sh
# Local packaging only. No signing, accounts, uploading or third-party installation.
# The resulting IPA CANNOT be installed until separately signed on the user's device route.
set -eu
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != "Darwin" ]; then
  echo "Requires macOS with Xcode; no build was attempted." >&2
  exit 1
fi
project_root="$(pwd)"
derived_path="$project_root/build/UnsignedDerivedData"
package_path="$project_root/build/UnsignedPackage"
xcodebuild -project FrameGuide.xcodeproj -scheme FrameGuide -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$derived_path" \
  CODE_SIGNING_ALLOWED=NO build
app_path="$derived_path/Build/Products/Release-iphoneos/FrameGuide.app"
test -d "$app_path"
platform_name="$(plutil -extract CFBundleSupportedPlatforms.0 raw -o - "$app_path/Info.plist")"
if [ "$platform_name" != "iPhoneOS" ]; then
  echo "Refusing a simulator/non-iPhoneOS app." >&2
  exit 1
fi
xcrun lipo -verify_arch arm64 "$app_path/FrameGuide"
xcrun vtool -show-build "$app_path/FrameGuide" | grep -Eq 'platform[[:space:]]+IOS$'
if [ -e "$package_path/Payload" ] || [ -e "$package_path/FrameGuide-unsigned.ipa" ]; then
  echo "Packaging output exists; choose a fresh checkout/output before rerunning. Nothing was removed." >&2
  exit 1
fi
mkdir -p "$package_path/Payload"
ditto "$app_path" "$package_path/Payload/FrameGuide.app"
(
  cd "$package_path"
  ditto -c -k --keepParent Payload FrameGuide-unsigned.ipa
  ipa_bytes="$(stat -f %z FrameGuide-unsigned.ipa)"
  if [ "$ipa_bytes" -gt 52428800 ]; then
    echo "IPA exceeds the 50 MiB artifact safety cap; do not upload." >&2
    exit 1
  fi
  shasum -a 256 FrameGuide-unsigned.ipa > FrameGuide-unsigned.ipa.sha256
)
echo "Prepared build/UnsignedPackage/FrameGuide-unsigned.ipa (UNSIGNED, not device-tested)."
