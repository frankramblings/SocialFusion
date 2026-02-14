#!/bin/bash

echo "🔍 SocialFusion iOS Deployment Debug Script"
echo "=========================================="

# Check basic Xcode configuration
echo "1. Checking Xcode configuration..."
xcode-select -p
xcrun --show-sdk-path --sdk iphoneos

# Check code signing
echo "2. Checking code signing..."
security find-identity -v -p codesigning

# Check device connection
echo "3. Checking connected devices..."
xcrun devicectl list devices

# Clean and rebuild project
echo "4. Cleaning project..."
cd "$(dirname "$0")"
rm -rf DerivedData/
xcodebuild clean -project SocialFusion.xcodeproj -scheme SocialFusion

echo "5. Solutions to try:"
echo "   ✅ CloudKit configuration fixed"
echo "   ✅ Enhanced startup logging added"
echo ""
echo "📋 Manual steps to try:"
echo "   1. In Xcode, Product → Clean Build Folder"
echo "   2. Delete app from device if installed"
echo "   3. Restart Xcode"
echo "   4. Restart your iPhone"
echo "   5. Try building to Simulator first"
echo "   6. Check iOS version compatibility (your device has iOS 18 beta)"
echo ""
echo "🔧 If still failing, try these Xcode settings:"
echo "   1. Build Settings → Code Signing → Automatically manage signing = YES"
echo "   2. Build Settings → iOS Deployment Target = 16.0"
echo "   3. Signing & Capabilities → Remove CloudKit temporarily"
echo ""
echo "📱 Device-specific troubleshooting:"
echo "   1. Settings → Privacy & Security → Developer Mode (enable if disabled)"
echo "   2. Settings → General → VPN & Device Management → Trust your developer certificate"
echo "   3. Unplug and replug device"
echo ""
echo "🚨 iOS 18 Beta Considerations:"
echo "   Your device is running iOS 18 beta (26.0). This may cause compatibility issues."
echo "   Consider testing on iOS 17 device or simulator if available." 