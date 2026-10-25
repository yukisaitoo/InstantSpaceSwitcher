#ifndef ISS_H
#define ISS_H

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
 * @brief Describes the current space state for the active display.
 */
typedef struct {
    unsigned int currentIndex; /**< Zero-based index of the active space */
    unsigned int spaceCount;   /**< Total number of user-visible spaces */
    char displayID[128];       /**< UUID string of the display */
} ISSSpaceInfo;

/**
 * @brief Performs the space switch if the requested move is within bounds.
 * @param direction The direction to switch spaces towards
 * @return true if the switch was posted, false if blocked by bounds or errors
 */
bool iss_switch(ISSDirection direction);

/**
 * @brief Retrieves the current space info for the active menu-bar display.
 * @param info Output pointer that receives the info struct.
 * @return true on success, false if unavailable (e.g. API failure)
 */
bool iss_get_menubar_space_info(ISSSpaceInfo *info);

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

/**
 * @brief Enables or disables experimental overlay detection.
 * When disabled, Mission Control and App Exposé are always reported as inactive.
 * @param enabled true to enable detection, false to disable.
 */
void iss_set_overlay_detection_enabled(bool enabled);

/**
 * @brief Sets the gesture speed for switches, from hotkeys and swipes alike.
 * @param speed The velocity value for the gesture
 */
void iss_set_gesture_speed(double speed);

/**
 * @brief Sets the gesture speed used when a switch lands on the first
 * space. Full-speed landings there can leave floating overlay windows
 * (e.g. FaceTime PiP) detached until the next transition.
 * @param speed The velocity value for first-space landings (default 160).
 */
void iss_set_edge_gesture_speed(double speed);

#endif /* ISS_H */
