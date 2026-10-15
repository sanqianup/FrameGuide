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
if [ -e "$package_path/Payload" ] || [ -e "$package_path/FrameGuide-unsigned.ipa" ]; then
  echo "Packaging output exists; choose a fresh checkout/output before rerunning. Nothing was removed." >&2
  exit 1
fi
mkdir -p "$package_path/Payload"
ditto "$app_path" "$package_path/Payload/FrameGuide.app"
(
  cd "$package_path"
  ditto -c -k --keepParent Payload FrameGuide-unsigned.ipa
  shasum -a 256 FrameGuide-unsigned.ipa > FrameGuide-unsigned.ipa.sha256
)
echo "Prepared build/UnsignedPackage/FrameGuide-unsigned.ipa (UNSIGNED, not device-tested)."
