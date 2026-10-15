#!/bin/sh
# Run manually on an available Mac. No network, credentials, signing or installation.
set -eu
cd "$(dirname "$0")/.."
xcodebuild -version
xcodebuild -showsdks
plutil -lint App/Info.plist App/PrivacyInfo.xcprivacy FrameGuide.xcodeproj/project.pbxproj
swift test --package-path Core
xcodebuild -project FrameGuide.xcodeproj -scheme FrameGuide -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FrameGuide.xcodeproj -scheme FrameGuide -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
