# Ship-Readiness Test Matrix

> Auto-verified by `run_tests.sh` matrix preflight.

| Wave | Owner | Test Suite | Priority | Status |
|------|-------|-----------|----------|--------|
| W0 | Release | `SocialFusionUITests/TimelineRegressionTests` | P0 | Present |
| W1 | Search | `SocialFusionTests/SearchPostRenderingTests` | P0 | Present |
| W1 | Search | `SocialFusionTests/SearchStoreTests` | P0 | Present |
| W1 | Navigation | `SocialFusionUITests/StateRestorationUITests` | P0 | Planned |
| W2 | Performance | `SocialFusionTests/DraftStoreIOTests` | P0 | Planned |
| W2 | Performance | `SocialFusionTests/ViewTrackerPerformanceTests` | P0 | Planned |
| W2 | Security | `SocialFusionTests/ReleaseLoggingTests` | P0 | Planned |
| W3 | UI | `SocialFusionUITests/ReachabilityUITests` | P1 | Planned |
| W3 | Media | `SocialFusionUITests/FullscreenMediaGestureUITests` | P1 | Planned |
| W4 | Platform | `SocialFusionUITests/ShareExtensionFlowUITests` | P1 | Planned |
| W4 | Intents | `SocialFusionTests/AppIntentsTests` | P1 | Planned |
| W4 | Notifications | `SocialFusionUITests/NotificationPermissionUITests` | P1 | Planned |
| W4 | iPad | `SocialFusionUITests/MultiSceneUITests` | P1 | Planned |

## Exit Criteria

- All suites present and passing before RC merge.
- `run_tests.sh` matrix preflight returns exit 0.
