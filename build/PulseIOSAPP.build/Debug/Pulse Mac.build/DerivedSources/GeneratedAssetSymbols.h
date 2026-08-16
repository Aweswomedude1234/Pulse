#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"nithilan.PulseIOSAPP.mac";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "PulseAppIcon" asset catalog image resource.
static NSString * const ACImageNamePulseAppIcon AC_SWIFT_PRIVATE = @"PulseAppIcon";

/// The "PulseAppLogo" asset catalog image resource.
static NSString * const ACImageNamePulseAppLogo AC_SWIFT_PRIVATE = @"PulseAppLogo";

/// The "PulseLogo" asset catalog image resource.
static NSString * const ACImageNamePulseLogo AC_SWIFT_PRIVATE = @"PulseLogo";

/// The "PulseLogoMark" asset catalog image resource.
static NSString * const ACImageNamePulseLogoMark AC_SWIFT_PRIVATE = @"PulseLogoMark";

#undef AC_SWIFT_PRIVATE
