# InstantSpaceSwitcher (fork)

Switch macOS spaces instantly, with no sliding animation.

https://github.com/user-attachments/assets/037422c9-3fb7-41cd-8da7-58d28c4c8eff

This is a personal fork of [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) by jurplel. It's trimmed down to left/right switching and has updates that I didn't want to wait on. Requires macOS 27.

## Features

- **Keyboard shortcuts**: switch one space left or right. Default binding is ⌃⌥⌘← / ⌃⌥⌘→ (I personally remapped to ⌃← / ⌃→).
- **Trackpad swipe override**: swipes between spaces become instant.
- **Switching modes**: Instant (default) jumps with no animation. Smooth plays a faster version of macOS's slide, which also avoids the slight flicker Instant has on FaceTime call spaces.
- **On-screen display**: a space number briefly appears when you switch.
- **Launch at login**
- Doesn't require disabling System Integrity Protection.

## Removed

- Jump-to-space shortcut (space 1–16)
- Jump to "last used space".
- The menu bar icon and its menu.
- The command-line tool (`ISSCli`).

## Fixes

- The app no longer resets its own Accessibility permission every launch.
- Shortcuts use macOS's standard hotkey API, so the app no longer watches all key inputs.
- Swiping no longer gets stuck if macOS briefly pauses the app mid-swipe.
- Swiping no longer needs to read key inputs for some odd reason.
- Switching no longer overshoots during Mission Control close animation.
- Switching no longer overshoot into an empty black space past the first or last space.
- FaceTime's call window no longer disappears when you switch to the space where you answered the call.

<details>
<summary>Tuning the FaceTime call window fix</summary>

A window that shows on every space, like FaceTime's call window, still belongs to the space it was opened on. An instant switch into that space can leave the window hidden, so those switches carry a little real swipe movement (default 0.25). You may see a slight flicker on those switches only; every other switch is unchanged. Values from 0.1 to 1.0 have worked. Lower flickers less. Changes apply on the next switch, no relaunch needed.

```sh
defaults write com.interversehq.InstantSpaceSwitcher floatingWindowProgress -float 0.1   # try a value
defaults delete com.interversehq.InstantSpaceSwitcher floatingWindowProgress             # back to the default (0.25)
```

</details>

<details>
<summary>Tuning the Smooth switching speed</summary>

Smooth mode's slide speed is set by its fling velocity (default 15). Lower is a slower slide, higher is closer to instant; around 10–30 is the useful range, and 40 or more looks nearly instant. Changes apply on the next switch, no relaunch needed.

```sh
defaults write com.interversehq.InstantSpaceSwitcher smoothFlingVelocity -float 20   # try a value
defaults delete com.interversehq.InstantSpaceSwitcher smoothFlingVelocity            # back to the default (15)
```

</details>

## Build from source

> [!IMPORTANT]
> Don't have the fork and the original app installed at the same time. Both use the same name and settings and fight over the same shortcuts and swipes.

Clone this repo, then:

```sh
./dist/make-dev-cert.sh   # once: keeps the Accessibility permission across rebuilds
./dist/build.sh           # builds, replaces /Applications/InstantSpaceSwitcher.app, relaunches
```

## Debugging

To watch what the app is doing (in zsh, `log` alone is a different built-in command):

```sh
/usr/bin/log stream --level debug --predicate 'subsystem == "com.interversehq.InstantSpaceSwitcher"'
```

## Switching between the original and this fork

**Original → this fork**

1. Quit the original. If you installed it with Homebrew, run `brew uninstall --cask instant-space-switcher`. If not, move it to the Trash.
2. Build and install this fork.
3. In System Settings > Privacy & Security > Accessibility, remove InstantSpaceSwitcher with −, relaunch it, and allow it when asked.

**This fork → original**

1. Quit the app and move it to the Trash.
2. Install the original. On first launch it resets its Accessibility permission and asks again, so allow it.
3. Optional: delete the "InstantSpaceSwitcher Dev" certificate. Open Keychain Access > go to login > My Certificates, and delete it.

## License

Same as the original. See [LICENSE](LICENSE).
