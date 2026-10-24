#include "../ISS/include/ISS.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <string.h>

static void print_usage(const char *progName) {
    fprintf(stderr, "Usage: %s [left|right]\n", progName);
}

int main(int argc, char **argv) {
    if (!iss_init()) {
        fprintf(stderr, "Failed to initialize ISS (event tap). Check accessibility and input monitoring permissions.\n");
        return 1;
    }

    ISSDirection direction = ISSDirectionLeft;

    if (argc > 1) {
        if (!strcmp(argv[1], "right") || !strcmp(argv[1], "r") || !strcmp(argv[1], "1")) {
            direction = ISSDirectionRight;
        } else if (!strcmp(argv[1], "left") || !strcmp(argv[1], "l") || !strcmp(argv[1], "0")) {
            direction = ISSDirectionLeft;
        } else {
            print_usage(argv[0]);
            iss_destroy();
            return 1;
        }
    }

    bool success = iss_switch(direction);

    if (!success) {
        fprintf(stderr, "Switch request failed. Check space bounds or permissions.\n");
        iss_destroy();
        return 1;
    }

    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.3, false);
    iss_destroy();
    return 0;
}
