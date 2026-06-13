#import "MPBridge.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>

// Declared so the compiler knows the selectors; never linked — the real class is
// resolved at runtime via NSClassFromString after dlopen, so [cls alloc] messages
// the genuine MonitorPanel class without a link-time dependency on it.
@interface MPDisplay : NSObject
- (instancetype)initWithCGSDisplayID:(int)displayID;
- (BOOL)canChangeOrientation;
@property (nonatomic) int orientation;
@end

static Class MPDisplayClass(void) {
    static Class cls = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_NOW);
        cls = NSClassFromString(@"MPDisplay");
    });
    return cls;
}

static MPDisplay *MakeDisplay(CGDirectDisplayID display) {
    Class cls = MPDisplayClass();
    if (!cls) return nil;
    return [(MPDisplay *)[cls alloc] initWithCGSDisplayID:(int)display];
}

BOOL OD_DisplayCanRotate(CGDirectDisplayID display) {
    MPDisplay *d = MakeDisplay(display);
    return d ? [d canChangeOrientation] : NO;
}

BOOL OD_DisplayRotate(CGDirectDisplayID display, int degrees) {
    MPDisplay *d = MakeDisplay(display);
    if (!d || ![d canChangeOrientation]) return NO;
    d.orientation = degrees;
    return YES;
}
