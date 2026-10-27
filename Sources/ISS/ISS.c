#include "include/ISS.h"
#include "cgs_private.h"
#include "event_serialize.h"

#include <mach/mach_time.h>
#include <os/log.h>
#include <string.h>

// The space state of the display under the cursor
typedef struct {
    unsigned int currentIndex;
    unsigned int spaceCount;
} ISSSpaceInfo;

static os_log_t swipeLog = NULL;

static CFMachPortRef globalTap = NULL;

static bool overlayDetectionEnabled = false;

static bool swipeOverrideEnabled = false;
static bool swipeTracking = false;
static bool swipeFired = false;

// Our macOS 27 swipes re-enter the tap with sourcePid == 0, so they carry this tag instead
static const int64_t kSyntheticEventTag = 0x495353; // "ISS"

// A swipe whose ended event never reached us would otherwise swallow every later trackpad gesture
static const CFTimeInterval kStaleSwipeTimeout = 1.0;
static CFAbsoluteTime lastSwipeEventTime = 0;

static ISSSwitchCallback switchCallback = NULL;

// A switch is confirmed by a space-change notification ~50ms after we post it,
// and only then does CGS report the new space. Switching again before that
// computes from the old space and can overshoot past the first or last one,
// which on macOS 27 shows a black space until the Dock bounces back. So only
// one switch is in flight; one still unconfirmed after kPendingSwitchTimeout is
// assumed dropped by the Dock.
static const CFTimeInterval kPendingSwitchTimeout = 0.5;
static CFAbsoluteTime pendingSwitchTime = 0; // 0 when no switch is in flight

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
        os_log_error(swipeLog, "required CGS symbols missing");
        return false;
    }

    CGSConnectionID connection = CGSMainConnectionID();
    if (connection == 0) {
        os_log_error(swipeLog, "CGSMainConnectionID returned 0");
        return false;
    }

    CGSSpaceID activeSpace = CGSGetActiveSpace(connection);
    if (activeSpace == 0) {
        os_log_error(swipeLog, "CGSGetActiveSpace returned 0");
        return false;
    }

    CFStringRef displayIdentifier = copy_cursor_display_uuid();

    CFArrayRef displays = CGSCopyManagedDisplaySpaces(connection);

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
        CFStringRef owner = CFDictionaryGetValue(info, kCGWindowOwnerName);
        CFNumberRef layerNumber = CFDictionaryGetValue(info, kCGWindowLayer);
        int layer = 0;
        if (!owner || !CFEqual(owner, CFSTR("Dock")) || !layerNumber ||
            !CFNumberGetValue(layerNumber, kCFNumberIntType, &layer)) {
            continue;
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
// leaves nothing to animate, and the velocity still commits the switch. Full progress
// switches too, but the previous space flashes before it lands.
static const double kMinimalSwipeProgress = 0.000016;

// The fling on the ended phase is what commits the switch on macOS 27. The payload
// field is 16.16 fixed point, which caps it at kMaxFlingVelocity.
static const double kFlingVelocity = 9999.0;
static const double kMaxFlingVelocity = 32767.0;

// Landing on the first space at full fling makes the Dock rubber-band, which
// leaves canJoinAllSpaces windows (FaceTime's call window) hidden until the next
// transition. Temporarily tunable with `defaults write <bundle id> firstSpaceFlingVelocity N`.
static double first_space_fling_velocity(void) {
    CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
    CFNumberRef value = CFPreferencesCopyAppValue(CFSTR("firstSpaceFlingVelocity"), kCFPreferencesCurrentApplication);
    double velocity = kFlingVelocity;
    if (value) {
        double configured = 0;
        // Zero or negative never commits a switch; above the max overflows the payload
        if (CFGetTypeID(value) == CFNumberGetTypeID() &&
            CFNumberGetValue(value, kCFNumberDoubleType, &configured) && configured > 0) {
            velocity = configured < kMaxFlingVelocity ? configured : kMaxFlingVelocity;
        }
        CFRelease(value);
    }
    return velocity;
}

// Cached natural scrolling preference; -1 means re-read it
static int naturalScrolling = -1;

static const CFStringRef kSwipeScrollDirectionChanged = CFSTR("SwipeScrollDirectionDidChangeNotification");

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
static double swipe_sign(ISSDirection direction) {
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

static bool post_dock_swipe(CGSGesturePhase phase, ISSDirection direction, double velocity) {
    const double sign = swipe_sign(direction);

    CGEventRef event = create_dock_swipe_event(phase);
    if (!event) {
        return false;
    }
    CGEventSetDoubleValueField(event, kCGEventGestureSwipeProgress, sign * kMinimalSwipeProgress);
    // Fields a real trackpad swipe carries (from FasterSwiper's traces).
    CGEventSetIntegerValueField(event, kCGEventGesturePhaseAlias, phase);
    CGEventSetDoubleValueField(event, kCGEventGestureZoomDeltaY, 3.0);
    CGEventSetDoubleValueField(event, kCGEventSourceUnixProcessIDAlias, (double)mach_absolute_time());
    CGEventSetDoubleValueField(event, kCGEventGestureSwipePositionX, 0.1);
    // Set before augmenting, which rebuilds the event from its serialized fields
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, kSyntheticEventTag);
    // Match FasterSwiper: only the Ended event carries velocity.
    if (phase == kCGSGesturePhaseEnded) {
        CGEventSetDoubleValueField(event, kCGEventGestureSwipeVelocityX, sign * velocity);
    }

    CGEventRef augmented = iss_create_augmented_dock_swipe_event(event);
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
    CGEventSetIntegerValueField(companion, kCGEventSourceUserData, kSyntheticEventTag);
    CGEventPost(kCGSessionEventTap, augmented);
    CGEventPost(kCGSessionEventTap, companion);
    CFRelease(augmented);
    CFRelease(companion);
    return true;
}

static bool perform_switch_gesture(ISSDirection direction, double velocity) {
    // All three phases are needed; with only two, Mission Control doesn't work.
    return post_dock_swipe(kCGSGesturePhaseBegan,   direction, velocity)
        && post_dock_swipe(kCGSGesturePhaseChanged, direction, velocity)
        && post_dock_swipe(kCGSGesturePhaseEnded,   direction, velocity);
}

static bool is_at_edge(const ISSSpaceInfo *info, ISSDirection direction) {
    return direction == ISSDirectionLeft ? info->currentIndex == 0 : info->currentIndex + 1 >= info->spaceCount;
}

bool iss_switch(ISSDirection direction) {
    const char *name = direction == ISSDirectionLeft ? "left" : "right";

    if (pendingSwitchTime != 0) {
        CFTimeInterval waited = CFAbsoluteTimeGetCurrent() - pendingSwitchTime;
        if (waited < kPendingSwitchTimeout) {
            os_log_debug(swipeLog, "switch %{public}s: busy, previous switch unconfirmed for %.0fms",
                         name, waited * 1000.0);
            return false;
        }
        os_log_debug(swipeLog, "switch %{public}s: previous switch was dropped", name);
        pendingSwitchTime = 0;
    }

    ISSSpaceInfo info;
    if (!load_space_info(&info)) {
        os_log_error(swipeLog, "switch %{public}s: no space info", name);
        return false;
    }
    if (is_at_edge(&info, direction)) {
        os_log_debug(swipeLog, "switch %{public}s: at edge (cgs=%u count=%u)", name, info.currentIndex, info.spaceCount);
        return false;
    }

    unsigned int target = direction == ISSDirectionLeft ? info.currentIndex - 1 : info.currentIndex + 1;
    double velocity = target == 0 ? first_space_fling_velocity() : kFlingVelocity;
    os_log_debug(swipeLog, "switch %{public}s: cgs=%u target=%u count=%u velocity=%.0f",
                 name, info.currentIndex, target, info.spaceCount, velocity);
    if (!perform_switch_gesture(direction, velocity)) {
        os_log_error(swipeLog, "switch %{public}s: posting the swipe failed", name);
        return false;
    }
    pendingSwitchTime = CFAbsoluteTimeGetCurrent();
    return true;
}

static void reset_swipe_state(void) {
    swipeTracking = false;
    swipeFired = false;
}

static bool is_gesture_event(CGSEventType eventType) {
    return eventType == kCGSEventDockControl || eventType == kCGSEventGesture;
}

// A physical swipe's sign ignores natural scrolling; only the posted swipe is flipped (see swipe_sign)
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
    lastSwipeEventTime = CFAbsoluteTimeGetCurrent();

    switch ((CGSGesturePhase)CGEventGetIntegerValueField(event, kCGEventGesturePhase)) {
    case kCGSGesturePhaseBegan:
        if (onscreen_windows_match(iss_is_expose_detected_in_window_list)) {
            os_log_debug(swipeLog, "began: App Expose detected, passing swipe through");
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
        CGEventTapEnable(globalTap, true);
        // The swipe's ended event may have slipped past while disabled
        reset_swipe_state();
        return event;
    }

    if (CGEventGetIntegerValueField(event, kCGEventSourceUserData) == kSyntheticEventTag) {
        return event;
    }

    CGSEventType eventType = (CGSEventType)CGEventGetIntegerValueField(event, kCGSEventTypeField);
    if (!swipeOverrideEnabled || !is_gesture_event(eventType)) {
        return event;
    }

    // Real trackpad gestures come from the HID system (sourcePid 0)
    pid_t sourcePid = (pid_t)CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
    if (sourcePid != 0) {
        return event;
    }

    if (eventType == kCGSEventDockControl) {
        return handle_dock_swipe(event);
    }

    // Keep tracking so a late ended event is still neutralized; the next Began resets it
    bool stale = CFAbsoluteTimeGetCurrent() - lastSwipeEventTime > kStaleSwipeTimeout;
    return swipeTracking && !stale ? NULL : event;
}

bool iss_init(void) {
    if (globalTap) {
        return true;
    }

    if (!swipeLog) {
        swipeLog = os_log_create("com.interversehq.InstantSpaceSwitcher", "swipe");
    }

    CGEventMask mask = CGEventMaskBit(kCGSEventGesture) | CGEventMaskBit(kCGSEventDockControl);
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

    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, globalTap, 0);
    if (!source) {
        CFRelease(globalTap);
        globalTap = NULL;
        return false;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);
    CGEventTapEnable(globalTap, true);

    naturalScrolling = -1;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(),
                                    &naturalScrolling, natural_scrolling_changed,
                                    kSwipeScrollDirectionChanged,
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    return true;
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

void iss_space_did_change(void) {
    ISSSpaceInfo info;
    bool loaded = load_space_info(&info);
    bool confirmsSwitch = pendingSwitchTime != 0;
    os_log_debug(swipeLog, "space changed: cgs=%d %{public}s", loaded ? (int)info.currentIndex : -1,
                 confirmsSwitch ? "confirms switch" : "external");
    pendingSwitchTime = 0;

    if (confirmsSwitch && loaded && switchCallback) {
        switchCallback(info.currentIndex);
    }
}

void iss_set_switch_callback(ISSSwitchCallback callback) {
    switchCallback = callback;
}
