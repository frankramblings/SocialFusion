#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.socialfusion.app";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "PrimaryColor" asset catalog color resource.
static NSString * const ACColorNamePrimaryColor AC_SWIFT_PRIVATE = @"PrimaryColor";

/// The "SecondaryColor" asset catalog color resource.
static NSString * const ACColorNameSecondaryColor AC_SWIFT_PRIVATE = @"SecondaryColor";

/// The "TextColor" asset catalog color resource.
static NSString * const ACColorNameTextColor AC_SWIFT_PRIVATE = @"TextColor";

/// The "BlueskyLogo" asset catalog image resource.
static NSString * const ACImageNameBlueskyLogo AC_SWIFT_PRIVATE = @"BlueskyLogo";

/// The "MastodonLogo" asset catalog image resource.
static NSString * const ACImageNameMastodonLogo AC_SWIFT_PRIVATE = @"MastodonLogo";

#undef AC_SWIFT_PRIVATE
