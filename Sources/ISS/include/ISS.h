#ifndef ISS_H
#define ISS_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>

bool iss_init(void);

typedef enum {
    ISSDirectionLeft = 0,
    ISSDirectionRight = 1
} ISSDirection;

// Returns false without posting if the move is out of bounds or the previous switch is unconfirmed.
bool iss_switch(ISSDirection direction);

// Replaces native horizontal Dock swipes with instant switches.
void iss_set_swipe_override(bool enabled);

// Called once each switch is confirmed; newSpaceIndex is zero-based. Pass NULL to clear.
typedef void (*ISSSwitchCallback)(unsigned int newSpaceIndex);
void iss_set_switch_callback(ISSSwitchCallback callback);

// Call from activeSpaceDidChangeNotification to confirm the in-flight switch.
void iss_space_did_change(void);

// When disabled, iss_is_mission_control_active and the Exposé check always report inactive.
void iss_set_overlay_detection_enabled(bool enabled);
bool iss_is_mission_control_active(void);

// Classify a CGWindowListCopyWindowInfo result. Public so tests can feed fixtures.
bool iss_is_expose_detected_in_window_list(CFArrayRef windowList);
bool iss_is_mission_control_detected_in_window_list(CFArrayRef windowList);

#endif /* ISS_H */
