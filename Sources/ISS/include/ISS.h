#ifndef ISS_H
#define ISS_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>

/** @brief Initialize resources
 * @return true on success, false on failure
 */
bool iss_init(void);

/** @brief Clean up resources */
void iss_destroy(void);

/** @brief The direction to switch spaces towards */
typedef enum {
    ISSDirectionLeft = 0,
    ISSDirectionRight = 1
} ISSDirection;

/**
 * @brief Performs the space switch if the requested move is within bounds.
 * @param direction The direction to switch spaces towards
 * @return true if the switch was posted, false if blocked by bounds or errors
 */
bool iss_switch(ISSDirection direction);

/**
 * @brief Enables or disables interception of trackpad horizontal swipe gestures.
 *
 * When enabled, native horizontal dock-swipe gestures are suppressed and
 * replaced with instant space switches (no sliding animation).
 * @param enabled true to intercept, false to pass gestures through normally.
 */
void iss_set_swipe_override(bool enabled);

/**
 * @brief Callback invoked after any successful space switch.
 * @param newSpaceIndex Zero-based index of the space that was switched to.
 */
typedef void (*ISSSwitchCallback)(unsigned int newSpaceIndex);

/**
 * @brief Registers a callback invoked after each successful space switch.
 * @param callback Function pointer, or NULL to clear.
 */
void iss_set_switch_callback(ISSSwitchCallback callback);

/**
 * @brief Resets the predicted space indices so the next bounds check falls back
 * to live CGS data. Call this whenever the active space changes externally
 * (e.g. from activeSpaceDidChangeNotification).
 */
void iss_reset_predictions(void);

/**
 * @brief Returns true when Mission Control is currently active.
 * Detects more Dock layer-20 windows than layer-18 ones.
 */
bool iss_is_mission_control_active(void);

/** @brief Returns true when a CGWindowListCopyWindowInfo list looks like App Exposé. */
bool iss_is_expose_detected_in_window_list(CFArrayRef windowList);

/** @brief Returns true when a CGWindowListCopyWindowInfo list looks like Mission Control. */
bool iss_is_mission_control_detected_in_window_list(CFArrayRef windowList);

/**
 * @brief Enables or disables experimental overlay detection.
 * When disabled, Mission Control and App Exposé are always reported as inactive.
 * @param enabled true to enable detection, false to disable.
 */
void iss_set_overlay_detection_enabled(bool enabled);

#endif /* ISS_H */
