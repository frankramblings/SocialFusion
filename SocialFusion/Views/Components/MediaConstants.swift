import SwiftUI

/// Standardized constants for media display across the app
enum MediaConstants {
    /// Corner radius values for different contexts
    enum CornerRadius {
        /// Standard feed images (SingleImageView, GridImageView, QuotePostView)
        static let feed: CGFloat = 12
        
        /// Compact reply row images
        static let compact: CGFloat = 10
        
        /// Fullscreen viewer
        static let fullscreen: CGFloat = 0  // No corners in fullscreen
    }
    
    /// Spacing values for grid layouts
    enum Spacing {
        /// Grid spacing between images
        static let grid: CGFloat = 4
        
        /// Padding around ALT badge
        static let altBadgeHorizontal: CGFloat = 8
        static let altBadgeVertical: CGFloat = 4
        
        /// Padding around images in feed
        static let imagePadding: CGFloat = 0  // Handled by parent
    }
    
    /// Visual polish values
    enum Visual {
        /// Shadow for images
        static let shadowColor = Color.black.opacity(0.05)
        static let shadowRadius: CGFloat = 2
        static let shadowY: CGFloat = 1
        
        /// Border for images
        static let borderOpacity: CGFloat = 0.05
        static let borderWidth: CGFloat = 0.5
    }
    
    /// Animation timing
    enum Animation {
        static let duration: Double = 0.2
        static let springResponse: Double = 0.4
        static let springDamping: Double = 0.8
    }
}

