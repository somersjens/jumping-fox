#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"Hakketjak.Jumping-Fox";

/// The "LaunchBackground" asset catalog color resource.
static NSString * const ACColorNameLaunchBackground AC_SWIFT_PRIVATE = @"LaunchBackground";

/// The "bear_no_background" asset catalog image resource.
static NSString * const ACImageNameBearNoBackground AC_SWIFT_PRIVATE = @"bear_no_background";

/// The "bunny_no_background" asset catalog image resource.
static NSString * const ACImageNameBunnyNoBackground AC_SWIFT_PRIVATE = @"bunny_no_background";

/// The "crab_no_background" asset catalog image resource.
static NSString * const ACImageNameCrabNoBackground AC_SWIFT_PRIVATE = @"crab_no_background";

/// The "dog_no_background" asset catalog image resource.
static NSString * const ACImageNameDogNoBackground AC_SWIFT_PRIVATE = @"dog_no_background";

/// The "elephant_no_background" asset catalog image resource.
static NSString * const ACImageNameElephantNoBackground AC_SWIFT_PRIVATE = @"elephant_no_background";

/// The "frog_no_background" asset catalog image resource.
static NSString * const ACImageNameFrogNoBackground AC_SWIFT_PRIVATE = @"frog_no_background";

/// The "lion_no_background" asset catalog image resource.
static NSString * const ACImageNameLionNoBackground AC_SWIFT_PRIVATE = @"lion_no_background";

/// The "no_background" asset catalog image resource.
static NSString * const ACImageNameNoBackground AC_SWIFT_PRIVATE = @"no_background";

/// The "octupus_no_background" asset catalog image resource.
static NSString * const ACImageNameOctupusNoBackground AC_SWIFT_PRIVATE = @"octupus_no_background";

/// The "pinquin_no_background" asset catalog image resource.
static NSString * const ACImageNamePinquinNoBackground AC_SWIFT_PRIVATE = @"pinquin_no_background";

#undef AC_SWIFT_PRIVATE
