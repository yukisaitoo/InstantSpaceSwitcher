#ifndef EVENT_SERIALIZE_H
#define EVENT_SERIALIZE_H

#include <ApplicationServices/ApplicationServices.h>

// macOS 27 ignores synthetic Dock swipes without the raw IOHID payload, so this
// returns a copy of the event with it appended, or NULL on failure.
CGEventRef iss_create_augmented_dock_swipe_event(CGEventRef event);

#endif /* EVENT_SERIALIZE_H */
