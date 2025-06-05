# SocialFusion Project Layout

## Overview
SocialFusion is a unified social media client for federated networks, currently supporting Mastodon and Bluesky with plans for additional networks.

## Directory Structure
```
SocialFusion/
├── .cursor/               # Cursor IDE configuration and rules
│   ├── rules/            # Cursor rules for project automation
│   └── context/          # Project context and documentation
├── SocialFusion/         # Main iOS app target
│   ├── Views/           # SwiftUI views
│   ├── Models/          # Data models
│   ├── ViewModels/      # View models
│   ├── Services/        # Network and data services
│   └── Utilities/       # Helper functions and extensions
├── SocialFusionTests/    # Unit tests
└── SocialFusionUITests/  # UI tests
```

## Key Components
- **Views**: SwiftUI views for the user interface
- **Models**: Data models for posts, users, and network-specific entities
- **ViewModels**: Business logic and state management
- **Services**: Network requests, data persistence, and API integrations
- **Utilities**: Shared functionality and extensions

## Development Guidelines
1. Follow SwiftUI best practices for iOS 16+ compatibility
2. Maintain clean architecture with clear separation of concerns
3. Ensure proper error handling and network state management
4. Write unit tests for critical business logic
5. Document public interfaces and complex implementations 