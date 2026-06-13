// C surface over the private MonitorPanel display-rotation API, kept in a separate
// ObjC target so alloc/init memory management stays automatic under ARC and the
// pure-Swift target needs no bridging header or extra link flags. The MonitorPanel
// framework is dlopen'd at runtime and the class is resolved by name, so nothing
// links against the private framework. Both calls return NO if rotation is
// unsupported on this display or the private API is unavailable on this macOS.

#import <CoreGraphics/CoreGraphics.h>
#import "CGVirtualDisplay.h"   // umbrella re-export so Swift sees the virtual-display classes

BOOL OD_DisplayCanRotate(CGDirectDisplayID display);
BOOL OD_DisplayRotate(CGDirectDisplayID display, int degrees);
