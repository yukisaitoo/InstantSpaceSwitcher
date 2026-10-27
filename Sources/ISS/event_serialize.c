#include "event_serialize.h"
#include "cgs_private.h"

#include <mach/mach_time.h>
#include <stdint.h>
#include <string.h>

#pragma pack(push, 1)

typedef struct {
    uint32_t size;
    uint32_t type;
    uint32_t options;
    uint8_t depth;
    uint8_t reserved[3];
} IOHIDEventBase;

typedef struct {
    IOHIDEventBase base;
    int32_t position_x;
    int32_t position_y;
    int32_t position_z;
    uint32_t swipe_mask;
    uint16_t gesture_motion;
    uint16_t gesture_flavor;
    int32_t swipe_progress;
} IOHIDDockSwipeEventData;

typedef struct {
    IOHIDEventBase base;
    int32_t velocity_x;
    int32_t velocity_y;
    int32_t velocity_z;
} IOHIDVelocityEventData;

typedef struct {
    uint64_t timestamp;
    uint64_t sender_id;
    uint32_t options;
    uint32_t attribute_length;
    uint32_t event_count;
} IOHIDSystemQueueElementHeader;

#pragma pack(pop)

_Static_assert(sizeof(IOHIDEventBase) == 16, "unexpected IOHID event base layout");
_Static_assert(sizeof(IOHIDDockSwipeEventData) == 40,
               "unexpected IOHID Dock swipe layout");
_Static_assert(sizeof(IOHIDVelocityEventData) == 28,
               "unexpected IOHID velocity layout");
_Static_assert(sizeof(IOHIDSystemQueueElementHeader) == 28,
               "unexpected IOHID queue header layout");

static const uint16_t kIOHIDGestureFlavorDockPrimary = 3;

// Field ID of the appended IOHID payload
static const uint16_t kIOHIDPayloadTag = 4205;

enum {
    kMaxPayloadLength = sizeof(IOHIDSystemQueueElementHeader) + sizeof(IOHIDDockSwipeEventData) +
                        sizeof(IOHIDVelocityEventData),
};

static int32_t double_to_fixed1616(double val) {
    return (int32_t)(val * 65536.0);
}

// Writes the payload into a buffer of kMaxPayloadLength zeroed bytes and returns its length.
static size_t fill_iohid_payload(CGEventRef event, uint8_t *payload) {
    int64_t phase = CGEventGetIntegerValueField(event, kCGEventGesturePhase);
    int64_t motion = CGEventGetIntegerValueField(event, kCGEventGestureSwipeMotion);
    double progress = CGEventGetDoubleValueField(event, kCGEventGestureSwipeProgress);
    double pos_x = CGEventGetDoubleValueField(event, kCGEventGestureSwipePositionX);
    double pos_y = CGEventGetDoubleValueField(event, kCGEventGestureSwipePositionY);
    double vel_x = CGEventGetDoubleValueField(event, kCGEventGestureSwipeVelocityX);
    double vel_y = CGEventGetDoubleValueField(event, kCGEventGestureSwipeVelocityY);
    int64_t swipe_mask = CGEventGetIntegerValueField(event, kCGEventGestureSwipeMask);

    bool include_velocity = (vel_x != 0.0 || vel_y != 0.0 || phase == kCGSGesturePhaseEnded);

    IOHIDSystemQueueElementHeader *header = (IOHIDSystemQueueElementHeader *)payload;
    uint64_t timestamp = CGEventGetTimestamp(event);
    if (timestamp == 0) {
        timestamp = mach_absolute_time();
    }
    header->timestamp = timestamp;
    header->event_count = include_velocity ? 2 : 1;

    IOHIDDockSwipeEventData *swipe = (IOHIDDockSwipeEventData *)(header + 1);
    swipe->base.size = sizeof(IOHIDDockSwipeEventData);
    swipe->base.type = kIOHIDEventTypeDockSwipe;
    swipe->base.options = (uint32_t)((phase & 0xFF) << 24);
    swipe->position_x = double_to_fixed1616(pos_x);
    swipe->position_y = double_to_fixed1616(pos_y);
    swipe->swipe_mask = (uint32_t)swipe_mask;
    swipe->gesture_motion = (uint16_t)motion;
    swipe->gesture_flavor = kIOHIDGestureFlavorDockPrimary;
    swipe->swipe_progress = double_to_fixed1616(progress);

    if (!include_velocity) {
        return sizeof(*header) + sizeof(*swipe);
    }

    IOHIDVelocityEventData *velocity = (IOHIDVelocityEventData *)(swipe + 1);
    velocity->base.size = sizeof(IOHIDVelocityEventData);
    velocity->base.type = kIOHIDEventTypeVelocity;
    velocity->base.depth = 1;
    velocity->velocity_x = double_to_fixed1616(vel_x);
    velocity->velocity_y = double_to_fixed1616(vel_y);
    return kMaxPayloadLength;
}

CGEventRef iss_create_augmented_dock_swipe_event(CGEventRef event) {
    CFDataRef original = CGEventCreateData(kCFAllocatorDefault, event);
    if (!original) {
        return NULL;
    }

    // Only format version 2 is known (first 4 bytes: 00 00 00 02)
    static const uint8_t kFormatVersion2[4] = {0, 0, 0, 2};
    if (CFDataGetLength(original) < 4 || memcmp(CFDataGetBytePtr(original), kFormatVersion2, 4) != 0) {
        CFRelease(original);
        return NULL;
    }

    CFMutableDataRef data = CFDataCreateMutableCopy(kCFAllocatorDefault, 0, original);
    CFRelease(original);
    if (!data) {
        return NULL;
    }

    uint8_t payload[kMaxPayloadLength] = {0};
    size_t payload_length = fill_iohid_payload(event, payload);

    // The tag is two big-endian 16-bit words: the payload length in bytes, then the field ID
    const uint8_t tag[4] = {
        (uint8_t)(payload_length >> 8), (uint8_t)payload_length,
        (uint8_t)(kIOHIDPayloadTag >> 8), (uint8_t)kIOHIDPayloadTag,
    };
    CFDataAppendBytes(data, tag, sizeof(tag));
    CFDataAppendBytes(data, payload, (CFIndex)payload_length);

    CGEventRef result = CGEventCreateFromData(kCFAllocatorDefault, data);
    CFRelease(data);
    return result;
}
