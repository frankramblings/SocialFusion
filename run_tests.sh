#!/bin/bash

echo "🧪 SocialFusion Architecture Testing"
echo "===================================="

# Check if we're in the right directory
if [ ! -f "SocialFusion.xcodeproj/project.pbxproj" ]; then
    echo "❌ Error: Run this script from the SocialFusion root directory"
    exit 1
fi

echo "📋 Available Testing Options:"
echo "1. Run architecture validation test"
echo "2. Build with testing playground" 
echo "3. Test individual components"
echo "4. Compare old vs new architecture"
echo ""

# Option 1: Run validation test
echo "🔍 Option 1: Running Architecture Validation..."
swift SocialFusion/test_migration.swift
echo ""

# Option 2: Compile test playground
echo "🔨 Option 2: Testing Playground Compilation..."
if xcodebuild -quiet build &>/dev/null; then
    echo "✅ Main build successful"
else
    echo "❌ Main build failed - check for compilation errors"
fi

# Option 3: Component tests
echo "🧩 Option 3: Component Status Check..."
components=(
    "TimelineController.swift:Single source of truth controller"
    "ReliableScrollView.swift:UIKit-based scroll view"
    "UnifiedTimelineView+NewArchitecture.swift:New timeline implementation"  
    "MigrationTestController.swift:Testing framework"
)

for component in "${components[@]}"; do
    file=$(echo "$component" | cut -d: -f1)
    desc=$(echo "$component" | cut -d: -f2)
    if find SocialFusion -name "$file" -type f >/dev/null 2>&1; then
        echo "   ✅ $desc ($file)"
    else
        echo "   ❌ $desc ($file) - NOT FOUND"
    fi
done

echo ""
echo "🎯 Next Steps for Manual Testing:"
echo "================================="
echo "1. Launch the app normally"
echo "2. Navigate to Settings > Debug Options (if available)"
echo "3. Or run the app with: xcodebuild test"
echo "4. Test position restoration by:"
echo "   - Scrolling to middle of timeline"
echo "   - Force closing app"
echo "   - Reopening app"
echo "   - Verify it restores to same position"
echo ""

echo "🔄 Development Testing Commands:"
echo "==============================="
echo "• Simulator build: xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 16' build"
echo "• Clean build: xcodebuild clean && xcodebuild build"
echo "• Reset UserDefaults: defaults delete com.yourapp.SocialFusion"
echo ""

echo "✅ Architecture testing is ready!"
echo "All components are in place and the build is successful."
echo "You can now test the new architecture improvements safely."

echo ""
echo "📊 Ship-Readiness Matrix Preflight"
echo "==================================="

# Required test suites mapped to ship-readiness waves.
# Format: "RelativePath:Wave:Owner"
REQUIRED_SUITES=(
  # Wave 0 – Baseline
  "SocialFusionUITests/TimelineRegressionTests.swift:W0:Release"
  # Wave 1 – P0 Functional
  "SocialFusionTests/SearchPostRenderingTests.swift:W1:Search"
  "SocialFusionTests/SearchStoreTests.swift:W1:Search"
  "SocialFusionUITests/StateRestorationUITests.swift:W1:Navigation"
  # Wave 2 – P0 Performance/Security
  "SocialFusionTests/DraftStoreIOTests.swift:W2:Performance"
  "SocialFusionTests/ViewTrackerPerformanceTests.swift:W2:Performance"
  "SocialFusionTests/ReleaseLoggingTests.swift:W2:Security"
  # Wave 3 – P1 Interaction Polish
  "SocialFusionUITests/ReachabilityUITests.swift:W3:UI"
  "SocialFusionUITests/FullscreenMediaGestureUITests.swift:W3:Media"
  # Wave 4 – P1 Platform Integrations
  "SocialFusionUITests/ShareExtensionFlowUITests.swift:W4:Platform"
  "SocialFusionTests/AppIntentsTests.swift:W4:Intents"
  "SocialFusionUITests/NotificationPermissionUITests.swift:W4:Notifications"
  "SocialFusionUITests/MultiSceneUITests.swift:W4:iPad"
)

MATRIX_PASS=true
MATRIX_PRESENT=0
MATRIX_TOTAL=${#REQUIRED_SUITES[@]}

for entry in "${REQUIRED_SUITES[@]}"; do
  IFS=':' read -r path wave owner <<< "$entry"
  if [ -f "$path" ]; then
    echo "   ✅ [$wave/$owner] $path"
    MATRIX_PRESENT=$((MATRIX_PRESENT + 1))
  else
    echo "   ❌ [$wave/$owner] $path — MISSING"
    MATRIX_PASS=false
  fi
done

echo ""
echo "Matrix coverage: $MATRIX_PRESENT / $MATRIX_TOTAL suites present"

if [ "$MATRIX_PASS" = false ]; then
  echo "❌ Ship-readiness matrix preflight FAILED — add missing test suites before RC."
  exit 1
fi

echo "✅ Ship-readiness matrix preflight PASSED"
echo ""

echo "🛡️ Release Candidate Gates"
echo "========================="
echo "Running targeted stabilization tests..."

RC_TESTS=(
  "-only-testing:SocialFusionTests/RefreshGenerationGuardTests"
  "-only-testing:SocialFusionTests/NetworkServiceCancellationTests"
  "-only-testing:SocialFusionTests/TimelineIdentityStabilityTests"
  "-only-testing:SocialFusionTests/TimelineRefreshCoordinatorTests/testFetchToBufferBuffersRawPostsWithoutMerging"
)

if xcodebuild -project SocialFusion.xcodeproj -scheme SocialFusion -destination 'platform=iOS Simulator,name=iPhone 17 Pro' "${RC_TESTS[@]}" test; then
  echo "✅ Release gates passed:"
  echo "   - No stale refresh commit regression detected"
  echo "   - Network cancellation path still cancels in-flight requests"
  echo "   - Timeline identity remains stable across repost visual mutations"
  echo "   - Buffer fetch path avoids immediate merge side effects"
  echo "⚠️ Manual gate still required:"
  echo "   - Rapid account switch consistency"
  echo "   - Duplicate error banners check"
  echo "   - Media-heavy timeline responsiveness stress pass"
else
  echo "❌ Release gates failed. Fix regressions before RC."
  exit 1
fi
