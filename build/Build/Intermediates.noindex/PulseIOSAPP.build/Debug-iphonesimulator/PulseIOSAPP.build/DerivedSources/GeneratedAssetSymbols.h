#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "PulseAppIcon" asset catalog image resource.
static NSString * const ACImageNamePulseAppIcon AC_SWIFT_PRIVATE = @"PulseAppIcon";

/// The "PulseLogo" asset catalog image resource.
static NSString * const ACImageNamePulseLogo AC_SWIFT_PRIVATE = @"PulseLogo";

/// The "PulseLogoMark" asset catalog image resource.
static NSString * const ACImageNamePulseLogoMark AC_SWIFT_PRIVATE = @"PulseLogoMark";

#undef AC_SWIFT_PRIVATE
