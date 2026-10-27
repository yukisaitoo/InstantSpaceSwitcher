#ifndef CGS_PRIVATE_H
#define CGS_PRIVATE_H

// Undocumented CoreGraphics functions, CGEvent fields and values used to read
// spaces and to read and post Dock swipes.

#include <ApplicationServices/ApplicationServices.h>

typedef int32_t CGSConnectionID;
typedef uint64_t CGSSpaceID;

extern CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID connection) __attribute__((weak_import));
extern CGSConnectionID CGSMainConnectionID(void) __attribute__((weak_import));
extern CGSSpaceID CGSGetActiveSpace(CGSConnectionID connection) __attribute__((weak_import));

enum {
    kCGSEventTypeField = 55,
    kCGEventGestureHIDType = 110,
    kCGEventGestureSwipeMask = 115,
    kCGEventGestureSwipeMotion = 123,
    kCGEventGestureSwipeProgress = 124,
    kCGEventGestureSwipePositionX = 125,
    kCGEventGestureSwipePositionY = 126,
    kCGEventGestureSwipeVelocityX = 129,
    kCGEventGestureSwipeVelocityY = 130,
    kCGEventGesturePhase = 132,
    kCGEventGesturePhaseAlias = 134,
    kCGEventGestureZoomDeltaY = 138,
    // Real swipes carry a mach timestamp here, despite the name
    kCGEventSourceUnixProcessIDAlias = 169,
};

// See IOHIDEventType enum in IOHIDFamily
enum {
    kIOHIDEventTypeVelocity = 9,
    kIOHIDEventTypeDockSwipe = 23,
};

typedef uint32_t CGSEventType;
enum {
    kCGSEventGesture = 29,
    kCGSEventDockControl = 30,
};

typedef CF_ENUM(uint8_t, CGSGesturePhase) {
    kCGSGesturePhaseBegan = 1,
    kCGSGesturePhaseChanged = 2,
    kCGSGesturePhaseEnded = 4,
    kCGSGesturePhaseCancelled = 8,
};

enum {
    kCGGestureMotionHorizontal = 1,
};

#endif /* CGS_PRIVATE_H */
