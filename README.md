# SocialFusion

> **⚠️ ALPHA SOFTWARE** 
> 
> SocialFusion is currently in early alpha development. Expect bugs, incomplete features, and frequent changes. Not recommended for production use.

<div align="center">
  <img src="https://img.shields.io/badge/iOS-16.0+-blue.svg" alt="iOS Version">
  <img src="https://img.shields.io/badge/Swift-6.0-orange.svg" alt="Swift Version">
  <img src="https://img.shields.io/badge/Xcode-14.0+-blue.svg" alt="Xcode Version">
  <img src="https://img.shields.io/badge/Status-Alpha-red.svg" alt="Development Status">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License">
</div>
<br>
<div align="center">
  <img src="Github%20header.png" alt="SocialFusion Header">
</div>

## Overview

SocialFusion is a modern iOS app that provides a unified timeline experience for multiple social media platforms. Built with SwiftUI and designed for iOS 16+, it allows users to manage and view content from **Mastodon** and **Bluesky** in a single, elegant interface.

## ✨ Features

### 🌐 Multi-Platform Support
- **Mastodon** integration with full federation support
- **Bluesky** integration with AT Protocol
- Unified timeline showing posts from all connected accounts
- Platform-specific branding and visual indicators

### 📱 Native iOS Experience
- Built entirely with SwiftUI for optimal performance
- iOS 16+ compatibility with forward compatibility for iOS 17+
- Support for all device orientations (iPhone and iPad)
- Native iOS design patterns and interactions

### 🔐 Secure Authentication
- OAuth integration for Mastodon instances
- Secure token management with Keychain storage
- Multi-account support for each platform
- Account switching and management

### 📝 Rich Content Display
- **Link Previews** with intelligent metadata extraction
- **Quote Post** support across platforms
- **Media galleries** with fullscreen viewing
- **Poll display** and interaction
- Rich text formatting and emoji support

### ⚡ Advanced Timeline Features
- **Infinite scroll** with intelligent loading
- **Pull-to-refresh** functionality
- **Double-tap to scroll** to top/saved position
- Account-specific filtering
- Real-time timeline updates

### 💬 Interactive Features
- Post composition with rich formatting
- Like, repost, and reply functionality
- Quote posting and thread support
- Media attachment support
- Link preview selection

### 🎨 Beautiful Design
- Modern, clean interface following iOS design guidelines
- Dark and light mode support
- Platform-specific color theming
- Smooth animations and transitions
- Accessible design with VoiceOver support

## 🚀 Getting Started

### Prerequisites

- **Xcode 14.0+**
- **iOS 16.0+** deployment target
- **Swift 6.0**
- macOS 13.0+ for development

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/SocialFusion.git
   cd SocialFusion
   ```

2. **Open the project**
   ```bash
   open SocialFusion.xcodeproj
   ```

3. **Configure your development team**
   - In Xcode, select the project file
   - Update the `DEVELOPMENT_TEAM` in the project settings
   - Ensure your bundle identifier is unique

4. **Build and run**
   - Select your target device or simulator
   - Press `⌘+R` to build and run

### Dependencies

SocialFusion uses minimal external dependencies:
- **Swift Log** - For logging and debugging
- **Swift Testing** - For unit and integration tests

## 📋 Requirements

### System Requirements
- **iOS 16.0** or later
- **iPhone** and **iPad** support
- Network connectivity for social media APIs

### Developer Requirements
- **Xcode 14.0** or later
- **macOS 13.0** or later
- Apple Developer account (for device testing)

## 🏗️ Architecture

SocialFusion follows a clean, modular architecture:

### Core Components

- **Models**: Data structures for posts, accounts, and social platforms
- **Services**: Network layer handling API communication
- **ViewModels**: Business logic and state management
- **Views**: SwiftUI views and components
- **Utilities**: Helper functions and extensions

### Key Services

- **SocialServiceManager**: Orchestrates all social media services
- **MastodonService**: Handles Mastodon API integration
- **BlueskyService**: Manages Bluesky AT Protocol communication
- **AccountManager**: Manages user accounts and authentication
- **URLService**: Handles link detection and validation

### Data Flow

1. **Authentication** → Keychain storage → Account management
2. **API Requests** → Service layer → Data normalization
3. **Timeline Updates** → State management → UI updates
4. **User Interactions** → ViewModels → Service calls

## 🔧 Configuration

### Social Media Setup

**For Mastodon:**
1. The app supports any Mastodon instance
2. Users authenticate via OAuth web flow
3. Instance URL validation and capabilities detection

**For Bluesky:**
1. Direct authentication with Bluesky Social
2. AT Protocol integration
3. Handle and DID resolution

### App Transport Security

The app includes specific ATS configurations for:
- Various media domains for link previews
- Social media instance support
- Secure HTTPS enforcement where possible

## 🧪 Testing

Run the test suite:
```bash
# From Xcode
⌘+U

# From command line
xcodebuild test -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Test Coverage

- Model validation and data transformation
- Network service integration
- URL detection and validation
- Authentication flow testing
- UI component testing

## 📖 Documentation

Additional documentation is available:

- [Link and Quote Post Stabilization](LINK_AND_QUOTE_POST_STABILIZATION.md)
- [Launch Animation Implementation](LAUNCH_ANIMATION_IMPLEMENTATION_SUMMARY.md)
- [Infinite Scroll Implementation](INFINITE_SCROLL_IMPLEMENTATION.md)

## 🤝 Contributing

We welcome contributions! Please see our contributing guidelines:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Development Guidelines

- Follow iOS development best practices
- Maintain iOS 16+ compatibility
- Write unit tests for new features
- Update documentation as needed
- Follow existing code style and patterns

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Mastodon](https://mastodon.social) for the federated social network
- [Bluesky](https://bsky.app) for the AT Protocol implementation
- The iOS development community for excellent resources and tools

## 🧪 Alpha Testing

### Known Issues
- Occasional timeline loading failures
- Some edge cases in reply threading
- Media loading performance needs optimization
- Limited error messaging for network failures

### Testing Checklist
- [ ] Basic timeline loading and scrolling
- [ ] Account authentication (Mastodon & Bluesky)
- [ ] Post interactions (like, repost, reply)
- [ ] Media viewing and link previews
- [ ] Reply banner expansion and threading

### Reporting Issues
Please include:
- Device model and iOS version
- Steps to reproduce the bug
- Expected vs actual behavior
- Screenshots if relevant
- Console logs if available

## 📞 Support

- **Issues**: Please use GitHub Issues for bug reports and feature requests
- **Discussions**: Use GitHub Discussions for questions and community support
- **Security**: Report security issues privately via email

## 🔮 Alpha Roadmap

### Priority Alpha Goals
- **Stability improvements** - Fix remaining crashes and edge cases
- **Core feature completion** - Reliable posting, liking, reposting
- **Performance optimization** - Smooth scrolling and loading
- **Basic accessibility** - VoiceOver support and contrast improvements
- **Error handling** - Better user feedback for failures

### Future Beta Goals
- Advanced filtering and search capabilities
- Offline reading and sync
- Additional social platform integrations
- Custom timeline organization
- Enhanced media support

### Post-Beta Considerations
- macOS companion app
- watchOS notifications and widgets
- Siri Shortcuts integration
- Advanced customization options

---

<div align="center">
  Made with ❤️ for the open social web
</div>