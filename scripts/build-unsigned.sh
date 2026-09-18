#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'This build requires macOS and Xcode. Run it through GitHub Actions, not Windows or Linux.' >&2
  exit 1
fi
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
plutil -lint Shiguang/Info.plist Shiguang/PrivacyInfo.xcprivacy Shiguang.xcodeproj/project.pbxproj
xcodebuild -project Shiguang.xcodeproj -scheme Shiguang \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=YES build
app_path="$project_root/build/Build/Products/Release-iphoneos/Shiguang.app"
test -f "$app_path/Shiguang"
test -f "$app_path/Info.plist"
xcrun lipo -verify_arch arm64 "$app_path/Shiguang"
staging_dir="$(mktemp -d)"
mkdir -p "$staging_dir/Payload" "$project_root/dist"
ditto "$app_path" "$staging_dir/Payload/Shiguang.app"
ditto -c -k --keepParent "$staging_dir/Payload" "$project_root/dist/Shiguang-unsigned.ipa"
unzip -tq "$project_root/dist/Shiguang-unsigned.ipa"
echo 'Created dist/Shiguang-unsigned.ipa. Sign locally with your Apple account before installing.'
