#include "include/ISS.h"
#include "cgs_private.h"
#include "event_serialize.h"

#include <ApplicationServices/ApplicationServices.h>
#include <mach/mach_time.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

// The space state of the display under the cursor
typedef struct {
    unsigned int currentIndex; // Zero-based index of the active space
    unsigned int spaceCount;   // Total number of user-visible spaces
    char displayID[128];       // UUID string of the display
} ISSSpaceInfo;

static CFMachPortRef globalTap = NULL;
static CFRunLoopSourceRef globalSource = NULL;

static bool overlayDetectionEnabled = false;

static bool swipeOverrideEnabled = false;
static bool swipeTracking = false;
static bool swipeFired = false;

// Our macOS 27 swipes re-enter the tap with sourcePid == 0, so count them out instead
static unsigned int syntheticEventsToPassThrough = 0;

static ISSSwitchCallback switchCallback = NULL;

static const CFStringRef kSwipeScrollDirectionChanged = CFSTR("SwipeScrollDirectionDidChangeNotification");

// DisplayID (CFStringRef) -> Index (CFNumberRef)
static CFMutableDictionaryRef predictionsDict = NULL;

// While our own gestures are still being animated, CGS reports an
// intermediate space and the Dock fires space-change notifications for each
// hop. Trusting either during a burst makes us overshoot past the last space,
// which on macOS 27 wedges the Dock (black screen) until it times out. Keep
// predictions authoritative until the Dock has been quiet for this long.
static const CFTimeInterval kPredictionTTL = 1.0;
static CFAbsoluteTime lastGestureTime = 0;

static bool gestures_in_flight(void) {
    return CFAbsoluteTimeGetCurrent() - lastGestureTime < kPredictionTTL;
}

static bool get_prediction(const char *displayID, unsigned int *outIndex) {
    if (!displayID || !predictionsDict) {
        return false;
    }
    if (!gestures_in_flight()) {
        CFDictionaryRemoveAllValues(predictionsDict);
        return false;
    }

    CFStringRef key = CFStringCreateWithCString(NULL, displayID, kCFStringEncodingUTF8);
    CFNumberRef value = CFDictionaryGetValue(predictionsDict, key);
    CFRelease(key);

    if (!value) {
        return false;
    }
    CFNumberGetValue(value, kCFNumberIntType, outIndex);
    return true;
}

static void set_prediction(const char *displayID, unsigned int index) {
    if (!displayID || !predictionsDict) {
        return;
    }

    CFStringRef key = CFStringCreateWithCString(NULL, displayID, kCFStringEncodingUTF8);
    CFNumberRef value = CFNumberCreate(NULL, kCFNumberIntType, &index);
    CFDictionarySetValue(predictionsDict, key, value);
    CFRelease(key);
    CFRelease(value);
}

static bool cgs_symbols_available(void) {
    return (&CGSMainConnectionID != NULL) &&
           (&CGSGetActiveSpace != NULL) &&
           (&CGSCopyManagedDisplaySpaces != NULL);
}

static bool get_space_id(const void *spaceValue, CGSSpaceID *outID) {
    if (!spaceValue || CFGetTypeID(spaceValue) != CFDictionaryGetTypeID()) {
        return false;
    }
    CFNumberRef idNumber = CFDictionaryGetValue(spaceValue, CFSTR("id64"));
    return idNumber && CFGetTypeID(idNumber) == CFNumberGetTypeID() &&
           CFNumberGetValue(idNumber, kCFNumberSInt64Type, outID);
}

static bool extract_space_info_from_display(CFDictionaryRef displayDict,
                                            CGSSpaceID globalActiveSpace,
                                            ISSSpaceInfo *outInfo) {
    CFStringRef identifier = CFDictionaryGetValue(displayDict, CFSTR("Display Identifier"));
    if (identifier && CFGetTypeID(identifier) == CFStringGetTypeID()) {
        CFStringGetCString(identifier, outInfo->displayID, sizeof(outInfo->displayID), kCFStringEncodingUTF8);
    }

    CFArrayRef spaces = CFDictionaryGetValue(displayDict, CFSTR("Spaces"));
    if (!spaces || CFGetTypeID(spaces) != CFArrayGetTypeID()) {
        return false;
    }

    // The display's own current space is more accurate than the global one
    CGSSpaceID activeSpace = 0;
    if (!get_space_id(CFDictionaryGetValue(displayDict, CFSTR("Current Space")), &activeSpace) ||
        activeSpace == 0) {
        activeSpace = globalActiveSpace;
    }

    unsigned int spaceCount = 0;
    bool foundActive = false;
    for (CFIndex i = 0; i < CFArrayGetCount(spaces); i++) {
        CGSSpaceID spaceID = 0;
        if (!get_space_id(CFArrayGetValueAtIndex(spaces, i), &spaceID)) {
            continue;
        }
        if (!foundActive && spaceID == activeSpace) {
            outInfo->currentIndex = spaceCount;
            foundActive = true;
        }
        spaceCount++;
    }

    outInfo->spaceCount = spaceCount;
    return foundActive;
}

static CFStringRef copy_cursor_display_uuid(void) {
    CGEventRef event = CGEventCreate(NULL);
    if (!event) {
        return NULL;
    }
    CGPoint cursorLocation = CGEventGetLocation(event);
    CFRelease(event);

    CGDirectDisplayID display = 0;
    uint32_t displayCount = 0;
    if (CGGetDisplaysWithPoint(cursorLocation, 1, &display, &displayCount) != kCGErrorSuccess || displayCount == 0) {
        return NULL;
    }

    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(display);
    if (!uuid) {
        return NULL;
    }
    CFStringRef uuidString = CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    return uuidString;
}

static CFDictionaryRef find_display_dict(CFArrayRef displays, CFStringRef identifier) {
    CFDictionaryRef firstDisplay = NULL;
    for (CFIndex i = 0; i < CFArrayGetCount(displays); i++) {
        CFDictionaryRef displayDict = CFArrayGetValueAtIndex(displays, i);
        if (!displayDict || CFGetTypeID(displayDict) != CFDictionaryGetTypeID()) {
            continue;
        }
        if (!firstDisplay) {
            firstDisplay = displayDict;
        }
        if (!identifier) {
            break;
        }

        CFStringRef displayIdentifier = CFDictionaryGetValue(displayDict, CFSTR("Display Identifier"));
        if (displayIdentifier && CFGetTypeID(displayIdentifier) == CFStringGetTypeID() &&
            CFEqual(displayIdentifier, identifier)) {
            return displayDict;
        }
    }
    return firstDisplay;
}

static bool load_space_info(ISSSpaceInfo *info) {
    memset(info, 0, sizeof(*info));

    if (!cgs_symbols_available()) {
        fprintf(stderr, "ISS: required CGS symbols missing\n");
        return false;
    }

    CGSConnectionID connection = CGSMainConnectionID();
    if (connection == 0) {
        fprintf(stderr, "ISS: CGSMainConnectionID returned 0\n");
        return false;
    }

    CGSSpaceID activeSpace = CGSGetActiveSpace(connection);
    if (activeSpace == 0) {
        fprintf(stderr, "ISS: CGSGetActiveSpace returned 0\n");
        return false;
    }

    CFStringRef displayIdentifier = copy_cursor_display_uuid();

    CFArrayRef displays = CGSCopyManagedDisplaySpaces(connection, displayIdentifier);
    if (!displays && displayIdentifier) {
        displays = CGSCopyManagedDisplaySpaces(connection, NULL);
    }

    bool success = false;
    if (displays) {
        CFDictionaryRef display = find_display_dict(displays, displayIdentifier);
        success = display && extract_space_info_from_display(display, activeSpace, info);
        CFRelease(displays);
    }
    if (displayIdentifier) {
        CFRelease(displayIdentifier);
    }
    return success;
}

static void scan_dock_window_list(CFArrayRef windowList,
                                  int *outLayer18Count,
                                  int *outLayer20Count) {
    *outLayer18Count = 0;
    *outLayer20Count = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(windowList); i++) {
        CFDictionaryRef info = CFArrayGetValueAtIndex(windowList, i);
        CFStringRef owner = CFDictionaryGetValue(info, CFSTR("kCGWindowOwnerName"));
        if (!owner || !CFEqual(owner, CFSTR("Dock"))) {
            continue;
        }
        int layer = 0;
        CFNumberRef layerNumber = CFDictionaryGetValue(info, CFSTR("kCGWindowLayer"));
        if (layerNumber) {
            CFNumberGetValue(layerNumber, kCFNumberIntType, &layer);
        }
        if (layer == 18) {
            (*outLayer18Count)++;
        } else if (layer == 20) {
            (*outLayer20Count)++;
        }
    }
}

// Both overlays show Dock windows at layers 18 and 20. App Exposé has no more
// layer-20 windows than layer-18 ones; Mission Control has more.
bool iss_is_expose_detected_in_window_list(CFArrayRef windowList) {
    int layer18Count = 0;
    int layer20Count = 0;
    scan_dock_window_list(windowList, &layer18Count, &layer20Count);
    return layer18Count > 0 && layer20Count > 0 && layer20Count <= layer18Count;
}

bool iss_is_mission_control_detected_in_window_list(CFArrayRef windowList) {
    int layer18Count = 0;
    int layer20Count = 0;
    scan_dock_window_list(windowList, &layer18Count, &layer20Count);
    return layer18Count > 0 && layer20Count > layer18Count;
}

static bool onscreen_windows_match(bool (*detect)(CFArrayRef windowList)) {
    if (!overlayDetectionEnabled) {
        return false;
    }
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (!windowList) {
        return false;
    }
    bool result = detect(windowList);
    CFRelease(windowList);
    return result;
}

bool iss_is_mission_control_active(void) {
    return onscreen_windows_match(iss_is_mission_control_detected_in_window_list);
}

// Rounds to the smallest non-zero 16.16 fixed-point value: it keeps the direction but
// leaves nothing to animate, and the velocity still commits the switch.
static const double kMinimalSwipeProgress = 0.000016;

// The fling on the ended phase is what commits the switch on macOS 27. The payload
// field is 16.16 fixed point (max ~32767), so the speed setting isn't reused here.
static const double kModernFlingVelocity = 9999.0;

// Cached natural scrolling preference; -1 means re-read it
static int naturalScrolling = -1;

// Posted by System Settings when the natural scrolling checkbox is toggled
static void natural_scrolling_changed(CFNotificationCenterRef center, void *observer,
                                      CFNotificationName name, const void *object,
                                      CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication);
    naturalScrolling = -1;
}

// On macOS 27 right is negative, and the Dock reads the posted sign through the
// natural scrolling preference, so it flips again with natural scrolling off.
static double modern_swipe_sign(ISSDirection direction) {
    if (naturalScrolling < 0) {
        Boolean valid = false;
        Boolean natural = CFPreferencesGetAppBooleanValue(CFSTR("com.apple.swipescrolldirection"),
                                                          kCFPreferencesAnyApplication, &valid);
        naturalScrolling = (!valid || natural) ? 1 : 0;
    }
    const double sign = (direction == ISSDirectionRight) ? -1.0 : 1.0;
    return naturalScrolling ? sign : -sign;
}

static CGEventRef create_dock_swipe_event(CGSGesturePhase phase) {
    CGEventRef event = CGEventCreate(NULL);
    if (!event) {
        return NULL;
    }
    CGEventSetIntegerValueField(event, kCGSEventTypeField, kCGSEventDockControl);
    CGEventSetIntegerValueField(event, kCGEventGestureHIDType, kIOHIDEventTypeDockSwipe);
    CGEventSetIntegerValueField(event, kCGEventGesturePhase, phase);
    CGEventSetIntegerValueField(event, kCGEventGestureSwipeMotion, kCGGestureMotionHorizontal);
    return event;
}

static bool post_dock_swipe(CGSGesturePhase phase, ISSDirection direction) {
    const double sign = modern_swipe_sign(direction);

    CGEventRef event = create_dock_swipe_event(phase);
    if (!event) {
        return false;
    }
    // Full progress switches too, but the previous space flashes before it lands.
    CGEventSetDoubleValueField(event, kCGEventGestureSwipeProgress, sign * kMinimalSwipeProgress);
    // Fields a real trackpad swipe carries (from FasterSwiper's traces).
    CGEventSetIntegerValueField(event, kCGEventGesturePhaseAlias, phase);
    CGEventSetDoubleValueField(event, kCGEventGestureZoomDeltaY, 3.0);
    CGEventSetDoubleValueField(event, kCGEventSourceUnixProcessIDAlias, (double)mach_absolute_time());
    CGEventSetDoubleValueField(event, kCGEventGestureSwipePositionX, 0.1);
    // Match FasterSwiper: only the Ended event carries velocity.
    if (phase == kCGSGesturePhaseEnded) {
        CGEventSetDoubleValueField(event, kCGEventGestureSwipeVelocityX, sign * kModernFlingVelocity);
    }

    CGEventRef augmented = iss_augment_dock_swipe_event(event);
    CFRelease(event);
    if (!augmented) {
        return false;
    }

    // The Dock ignores a DockControl event without a companion gesture event
    CGEventRef companion = CGEventCreate(NULL);
    if (!companion) {
        CFRelease(augmented);
        return false;
    }
    CGEventSetIntegerValueField(companion, kCGSEventTypeField, kCGSEventGesture);

    if (globalTap) {
        // Both events pass back through our own tap
        syntheticEventsToPassThrough += 2;
    }
    CGEventPost(kCGSessionEventTap, augmented);
    CGEventPost(kCGSessionEventTap, companion);
    CFRelease(augmented);
    CFRelease(companion);
    return true;
}

static bool perform_switch_gesture(ISSDirection direction) {
    // All three phases are needed; with only two, Mission Control doesn't work.
    lastGestureTime = CFAbsoluteTimeGetCurrent();
    return post_dock_swipe(kCGSGesturePhaseBegan,   direction)
        && post_dock_swipe(kCGSGesturePhaseChanged, direction)
        && post_dock_swipe(kCGSGesturePhaseEnded,   direction);
}

static bool should_block_switch(const ISSSpaceInfo *info, unsigned int current, ISSDirection direction) {
    return direction == ISSDirectionLeft ? current == 0 : current + 1 >= info->spaceCount;
}

bool iss_switch(ISSDirection direction) {
    ISSSpaceInfo info;
    if (!load_space_info(&info)) {
        return perform_switch_gesture(direction);
    }

    unsigned int predicted;
    unsigned int current = get_prediction(info.displayID, &predicted) ? predicted : info.currentIndex;
    if (should_block_switch(&info, current, direction)) {
        return false;
    }

    unsigned int target = direction == ISSDirectionLeft ? current - 1 : current + 1;
    if (!perform_switch_gesture(direction)) {
        return false;
    }
    set_prediction(info.displayID, target);
    if (switchCallback) {
        switchCallback(target);
    }
    return true;
}

static void reset_swipe_state(void) {
    swipeTracking = false;
    swipeFired = false;
}

static bool is_gesture_event(CGSEventType eventType) {
    return eventType == kCGSEventDockControl || eventType == kCGSEventGesture;
}

static void fire_once(double value) {
    if (swipeFired || value == 0.0) {
        return;
    }
    swipeFired = true;
    iss_switch(value > 0.0 ? ISSDirectionRight : ISSDirectionLeft);
}

static CGEventRef handle_dock_swipe(CGEventRef event) {
    uint32_t hidType = (uint32_t)CGEventGetIntegerValueField(event, kCGEventGestureHIDType);
    uint16_t motion = (uint16_t)CGEventGetIntegerValueField(event, kCGEventGestureSwipeMotion);
    if (hidType != kIOHIDEventTypeDockSwipe || motion != kCGGestureMotionHorizontal) {
        return event;
    }

    switch ((CGSGesturePhase)CGEventGetIntegerValueField(event, kCGEventGesturePhase)) {
    case kCGSGesturePhaseBegan:
        if (onscreen_windows_match(iss_is_expose_detected_in_window_list)) {
            return event;
        }
        swipeTracking = true;
        swipeFired = false;
        return NULL;

    case kCGSGesturePhaseChanged:
        if (!swipeTracking) {
            return event;
        }
        fire_once(CGEventGetDoubleValueField(event, kCGEventGestureSwipeProgress));
        return NULL;

    case kCGSGesturePhaseEnded:
        if (!swipeTracking) {
            return event;
        }
        fire_once(CGEventGetDoubleValueField(event, kCGEventGestureSwipeVelocityX));
        reset_swipe_state();
        // On macOS 27 the Dock needs the real ended event to close its gesture
        // state; zero the motion so it doesn't switch a second time
        CGEventSetDoubleValueField(event, kCGEventGestureSwipeProgress, 0.0);
        CGEventSetDoubleValueField(event, kCGEventGestureSwipeVelocityX, 0.0);
        CGEventSetDoubleValueField(event, kCGEventGestureSwipeVelocityY, 0.0);
        return event;

    case kCGSGesturePhaseCancelled:
        if (!swipeTracking) {
            return event;
        }
        reset_swipe_state();
        return NULL;

    default:
        return swipeTracking ? NULL : event;
    }
}

static CGEventRef event_tap_callback(CGEventTapProxy proxy, CGEventType type,
                                     CGEventRef event, void *refcon) {
    (void)proxy;
    (void)refcon;

    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (globalTap) {
            CGEventTapEnable(globalTap, true);
        }
        // Anything we posted while disabled never reaches us, so stop waiting for it
        syntheticEventsToPassThrough = 0;
        // The swipe's ended event may have slipped past while disabled
        reset_swipe_state();
        return event;
    }

    CGSEventType eventType = (CGSEventType)CGEventGetIntegerValueField(event, kCGSEventTypeField);

    // Our own events come back within milliseconds; a count left over after the
    // burst would let real trackpad swipes slip past the override
    if (syntheticEventsToPassThrough > 0 && !gestures_in_flight()) {
        syntheticEventsToPassThrough = 0;
    }

    if (syntheticEventsToPassThrough > 0 && is_gesture_event(eventType)) {
        syntheticEventsToPassThrough--;
        return event;
    }

    if (!swipeOverrideEnabled || !is_gesture_event(eventType)) {
        return event;
    }

    // Pass through synthetic events (non-HID source). Real gesture events
    // from the trackpad have sourcePid == 0 (HID kernel).
    pid_t sourcePid = (pid_t)CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
    if (sourcePid != 0) {
        return event;
    }

    if (eventType == kCGSEventDockControl) {
        return handle_dock_swipe(event);
    }

    return swipeTracking ? NULL : event;
}

bool iss_init(void) {
    if (globalTap) {
        return true;
    }

    if (!predictionsDict) {
        predictionsDict = CFDictionaryCreateMutable(NULL, 0, &kCFCopyStringDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    }

    // The key-event bits look vestigial (the callback never reads key events),
    // but removing them stops gesture events from being delivered to the tap,
    // so they stay. Verified empirically on macOS 26.
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp)
        | CGEventMaskBit(kCGSEventGesture) | CGEventMaskBit(kCGSEventDockControl);
    globalTap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        mask,
        event_tap_callback,
        NULL
    );
    if (!globalTap) {
        return false;
    }

    globalSource = CFMachPortCreateRunLoopSource(NULL, globalTap, 0);
    if (!globalSource) {
        CFRelease(globalTap);
        globalTap = NULL;
        return false;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), globalSource, kCFRunLoopCommonModes);
    CGEventTapEnable(globalTap, true);

    naturalScrolling = -1;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(),
                                    &naturalScrolling, natural_scrolling_changed,
                                    kSwipeScrollDirectionChanged,
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    return true;
}

void iss_destroy(void) {
    syntheticEventsToPassThrough = 0;
    if (predictionsDict) {
        CFRelease(predictionsDict);
        predictionsDict = NULL;
    }
    if (globalTap) {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDistributedCenter(),
                                           &naturalScrolling, kSwipeScrollDirectionChanged, NULL);
        CGEventTapEnable(globalTap, false);
        if (globalSource) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), globalSource, kCFRunLoopCommonModes);
            CFRelease(globalSource);
            globalSource = NULL;
        }
        CFRelease(globalTap);
        globalTap = NULL;
    }
}

void iss_set_swipe_override(bool enabled) {
    swipeOverrideEnabled = enabled;
    if (!enabled) {
        reset_swipe_state();
    }
}

void iss_set_overlay_detection_enabled(bool enabled) {
    overlayDetectionEnabled = enabled;
}

void iss_reset_predictions(void) {
    // Ignore the space-change notifications our own gestures cause (see kPredictionTTL)
    if (gestures_in_flight()) {
        return;
    }
    if (predictionsDict) {
        CFDictionaryRemoveAllValues(predictionsDict);
    }
}

void iss_set_switch_callback(ISSSwitchCallback callback) {
    switchCallback = callback;
}
