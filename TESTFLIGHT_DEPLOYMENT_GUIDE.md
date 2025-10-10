# SocialFusion TestFlight Deployment Guide

## Overview
This guide provides step-by-step instructions for deploying SocialFusion to TestFlight for beta testing.

## Prerequisites
- ✅ Xcode 17.0+ installed
- ✅ Apple Developer Account (Team ID: 9XH4G9XR8X)
- ✅ Development certificate and provisioning profile configured
- ✅ Archive successfully created (`SocialFusion.xcarchive`)

## Current Configuration Status
- **Bundle Identifier**: `com.emanueledigital.socialfusion`
- **Development Team**: 9XH4G9XR8X
- **Signing Identity**: Apple Development: Francis Emanuele (APN37S2B8F)
- **Provisioning Profile**: iOS Team Provisioning Profile (37ad586c-65e3-417f-8703-d307ebf23011)
- **Archive Location**: `/Users/frankemanuele/Documents/GitHub/SocialFusion/build/SocialFusion.xcarchive`

## Deployment Steps

### Step 1: Open Xcode Organizer
1. Open Xcode
2. Go to **Window** → **Organizer** (⌘⇧O)
3. Select the **Archives** tab
4. You should see the "SocialFusion" archive created today

### Step 2: Distribute App
1. Select the SocialFusion archive
2. Click **Distribute App**
3. Choose **App Store Connect** 
4. Click **Next**

### Step 3: Distribution Options
1. Select **Upload** (to send to App Store Connect)
2. Click **Next**
3. Keep default signing options (Automatically manage signing)
4. Click **Next**

### Step 4: Review and Upload
1. Review the app information
2. Click **Upload**
3. Wait for the upload to complete (this may take several minutes)

### Step 5: App Store Connect Configuration
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Sign in with your Apple Developer account
3. Navigate to **My Apps**
4. Find or create the SocialFusion app entry

### Step 6: TestFlight Setup
1. In App Store Connect, go to your app
2. Click on the **TestFlight** tab
3. Wait for the uploaded build to appear (can take 10-60 minutes)
4. Once available, click on the build number
5. Add **What to Test** notes for beta testers
6. Submit for beta app review if required

### Step 7: Add Beta Testers
1. In TestFlight, go to the **Internal Testing** or **External Testing** section
2. For **Internal Testing**: Add team members (up to 100 testers)
3. For **External Testing**: Add external beta testers (up to 10,000 testers)
4. Send invitations to testers

## Alternative: Command Line Distribution

If you prefer command line tools, you can use `altool` or `xcrun altool`:

```bash
# Upload to App Store Connect
xcrun altool --upload-app \
  --type ios \
  --file "/Users/frankemanuele/Documents/GitHub/SocialFusion/build/SocialFusion.xcarchive" \
  --username "your-apple-id@example.com" \
  --password "app-specific-password"
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Code Signing Issues
- **Problem**: "No matching provisioning profile found"
- **Solution**: 
  - Go to Xcode → Preferences → Accounts
  - Select your Apple ID and download provisioning profiles
  - In project settings, set "Automatically manage signing" to ON

#### 2. Archive Not Showing in Organizer
- **Problem**: Archive doesn't appear in Xcode Organizer
- **Solution**: 
  - Ensure you built for "Generic iOS Device" not simulator
  - Check that the archive is in the correct location
  - Refresh the Organizer window

#### 3. Upload Fails
- **Problem**: Upload to App Store Connect fails
- **Solution**:
  - Check your internet connection
  - Verify your Apple Developer account status
  - Try uploading during off-peak hours

#### 4. Missing App Store Connect Entry
- **Problem**: App doesn't exist in App Store Connect
- **Solution**:
  - Create a new app in App Store Connect
  - Use the same bundle identifier: `com.emanueledigital.socialfusion`
  - Fill in required metadata (name, description, etc.)

## App Store Connect Metadata Requirements

Before TestFlight distribution, ensure you have:

### Required Information
- [ ] App Name: "SocialFusion"
- [ ] App Description
- [ ] Keywords
- [ ] App Category: Social Networking
- [ ] Content Rating
- [ ] Privacy Policy URL (if collecting user data)
- [ ] Support URL

### Required Screenshots
- [ ] iPhone screenshots (6.7", 6.5", 5.5")
- [ ] iPad screenshots (12.9", 11")
- [ ] App icon (1024x1024px)

### Privacy Information
Since SocialFusion connects to Mastodon and Bluesky:
- [ ] Data collection practices
- [ ] Third-party SDK usage
- [ ] User authentication handling

## Beta Testing Best Practices

### For Internal Testing
1. Start with a small group of internal testers
2. Focus on core functionality validation
3. Test on different device types and iOS versions
4. Gather feedback on critical user flows

### For External Testing
1. Expand to a broader audience after internal validation
2. Include clear testing instructions
3. Set expectations for feedback timeline
4. Monitor crash reports and user feedback

## Version Management

### Build Numbers
- Each upload to TestFlight requires a unique build number
- Current version: Check `Info.plist` → `CFBundleVersion`
- Increment build number for each new upload

### Version Numbers
- Follow semantic versioning (e.g., 1.0.0, 1.0.1, 1.1.0)
- Update `CFBundleShortVersionString` in `Info.plist`

## Monitoring and Analytics

### TestFlight Feedback
- Monitor TestFlight feedback regularly
- Respond to tester questions promptly
- Track crash reports and fix critical issues

### Crash Reporting
- Enable crash reporting in Xcode Organizer
- Monitor crash logs in App Store Connect
- Fix high-frequency crashes before wider release

## Next Steps After TestFlight

1. **Gather Beta Feedback**: Collect and analyze tester feedback
2. **Fix Critical Issues**: Address any showstopper bugs
3. **Performance Optimization**: Monitor app performance metrics
4. **App Store Submission**: Prepare for full App Store release
5. **Marketing Preparation**: Prepare App Store listing and marketing materials

## Security Considerations

### API Keys and Secrets
- Ensure no hardcoded API keys in production builds
- Use proper keychain storage for sensitive data
- Implement certificate pinning for API communications

### User Data Protection
- Follow GDPR/CCPA compliance requirements
- Implement proper data encryption
- Provide clear privacy controls to users

## Support and Resources

- [Apple Developer Documentation](https://developer.apple.com/documentation/)
- [App Store Connect Help](https://help.apple.com/app-store-connect/)
- [TestFlight Beta Testing Guide](https://developer.apple.com/testflight/)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## Checklist for Beta Release

- [ ] Archive created successfully
- [ ] Code signing configured properly
- [ ] App uploaded to App Store Connect
- [ ] TestFlight metadata completed
- [ ] Internal testers added
- [ ] Beta testing instructions provided
- [ ] Crash reporting enabled
- [ ] Privacy policy updated
- [ ] Support channels established

---

**Note**: This deployment setup uses a development provisioning profile. For production release, you'll need to create a distribution provisioning profile and update the code signing settings accordingly.

**Last Updated**: October 10, 2025
**Archive Location**: `/Users/frankemanuele/Documents/GitHub/SocialFusion/build/SocialFusion.xcarchive`
