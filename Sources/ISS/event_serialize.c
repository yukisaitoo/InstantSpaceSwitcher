#include "event_serialize.h"
#include "cgs_private.h"

#include <ApplicationServices/ApplicationServices.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <stdlib.h>
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

// Tag of the appended payload: (Type << 14) | Field ID
static const uint16_t kIOHIDPayloadTag = 4205;

static int32_t double_to_fixed1616(double val) {
    int32_t fixed = (int32_t)(val * 65536.0);
    if (fixed == 0 && val != 0.0) {
        return val > 0.0 ? 1 : -1;
    }
    return fixed;
}

static uint8_t *generate_iohid_payload(CGEventRef event, size_t *out_length) {
    int64_t phase = CGEventGetIntegerValueField(event, kCGEventGesturePhase);
    int64_t motion = CGEventGetIntegerValueField(event, kCGEventGestureSwipeMotion);
    double progress = CGEventGetDoubleValueField(event, kCGEventGestureSwipeProgress);
    double pos_x = CGEventGetDoubleValueField(event, kCGEventGestureSwipePositionX);
    double pos_y = CGEventGetDoubleValueField(event, kCGEventGestureSwipePositionY);
    double vel_x = CGEventGetDoubleValueField(event, kCGEventGestureSwipeVelocityX);
    double vel_y = CGEventGetDoubleValueField(event, kCGEventGestureSwipeVelocityY);
    int64_t swipe_mask = CGEventGetIntegerValueField(event, kCGEventGestureSwipeMask);

    bool include_velocity = (vel_x != 0.0 || vel_y != 0.0 || phase == kCGSGesturePhaseEnded);
    uint32_t event_count = include_velocity ? 2 : 1;
    size_t payload_length = sizeof(IOHIDSystemQueueElementHeader) + sizeof(IOHIDDockSwipeEventData);
    if (include_velocity) {
        payload_length += sizeof(IOHIDVelocityEventData);
    }

    uint8_t *payload = calloc(1, payload_length);
    if (!payload) {
        return NULL;
    }

    IOHIDSystemQueueElementHeader *header = (IOHIDSystemQueueElementHeader *)payload;
    uint64_t timestamp = CGEventGetTimestamp(event);
    if (timestamp == 0) {
        timestamp = mach_absolute_time();
    }
    header->timestamp = timestamp;
    header->event_count = event_count;

    IOHIDDockSwipeEventData *swipe = (IOHIDDockSwipeEventData *)(payload + sizeof(IOHIDSystemQueueElementHeader));
    swipe->base.size = sizeof(IOHIDDockSwipeEventData);
    swipe->base.type = kIOHIDEventTypeDockSwipe;
    swipe->base.options = (uint32_t)((phase & 0xFF) << 24);
    swipe->position_x = double_to_fixed1616(pos_x);
    swipe->position_y = double_to_fixed1616(pos_y);
    swipe->swipe_mask = (uint32_t)swipe_mask;
    swipe->gesture_motion = (uint16_t)motion;
    swipe->gesture_flavor = kIOHIDGestureFlavorDockPrimary;
    swipe->swipe_progress = double_to_fixed1616(progress);

    if (include_velocity) {
        IOHIDVelocityEventData *velocity = (IOHIDVelocityEventData *)(payload + sizeof(IOHIDSystemQueueElementHeader) + sizeof(IOHIDDockSwipeEventData));
        velocity->base.size = sizeof(IOHIDVelocityEventData);
        velocity->base.type = kIOHIDEventTypeVelocity;
        velocity->base.depth = 1;
        velocity->velocity_x = double_to_fixed1616(vel_x);
        velocity->velocity_y = double_to_fixed1616(vel_y);
    }

    *out_length = payload_length;
    return payload;
}

CGEventRef iss_augment_dock_swipe_event(CGEventRef event) {
    if (!event) {
        return NULL;
    }

    CFDataRef data = CGEventCreateData(kCFAllocatorDefault, event);
    if (!data) {
        return NULL;
    }

    const uint8_t *bytes = CFDataGetBytePtr(data);
    CFIndex length = CFDataGetLength(data);

    // Only format version 2 is known (first 4 bytes: 00 00 00 02)
    if (length < 4 || bytes[0] != 0 || bytes[1] != 0 || bytes[2] != 0 || bytes[3] != 2) {
        CFRelease(data);
        return NULL;
    }

    size_t payload_length = 0;
    uint8_t *payload = generate_iohid_payload(event, &payload_length);
    if (!payload) {
        CFRelease(data);
        return NULL;
    }

    size_t new_length = (size_t)length + 4 + payload_length;
    uint8_t *new_bytes = malloc(new_length);
    if (!new_bytes) {
        free(payload);
        CFRelease(data);
        return NULL;
    }

    memcpy(new_bytes, bytes, length);
    // The tag is two big-endian 16-bit words: the payload length in bytes, then the tag ID
    new_bytes[length] = (uint8_t)((payload_length >> 8) & 0xFF);
    new_bytes[length + 1] = (uint8_t)(payload_length & 0xFF);
    new_bytes[length + 2] = (uint8_t)((kIOHIDPayloadTag >> 8) & 0xFF);
    new_bytes[length + 3] = (uint8_t)(kIOHIDPayloadTag & 0xFF);
    memcpy(new_bytes + length + 4, payload, payload_length);

    free(payload);
    CFRelease(data);

    CFDataRef new_data = CFDataCreate(kCFAllocatorDefault, new_bytes, (CFIndex)new_length);
    free(new_bytes);
    if (!new_data) {
        return NULL;
    }

    CGEventRef result = CGEventCreateFromData(kCFAllocatorDefault, new_data);
    CFRelease(new_data);
    return result;
}
