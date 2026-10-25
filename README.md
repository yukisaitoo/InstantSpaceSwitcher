# InstantSpaceSwitcher (fork)

Switch macOS spaces instantly, with no sliding animation.

https://github.com/user-attachments/assets/037422c9-3fb7-41cd-8da7-58d28c4c8eff

This is a personal fork of [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) by jurplel. It's trimmed down to left/right switching and has bug fixes I didn't want to wait on. Requires macOS 27.

## Features

- **Keyboard shortcuts**: switch one desktop space left or right. Default binding is ⌃⌥⌘← / ⌃⌥⌘→ (I personally remapped to ⌃← / ⌃→).
- **Trackpad swipe override**: swipes between desktop spaces become instant.
- **On-screen display**: a space number briefly appears when you switch.
- **Launch at login**
- Doesn't require disabling System Integrity Protection.

## Removed

- Jump-to-desktop-space shortcut (space 1–16)
- Jump to "last used desktop space".
- The menu bar icon and its menu.
- The command-line tool (`ISSCli`).

## Fixes

- The app no longer resets its own Accessibility permission every launch.
- Swiping no longer gets stuck if macOS briefly pauses the app mid-swipe.
- Quickly switching at the first or last desktop space no longer jumps the wrong way.
- Shortcuts must include ⌘, ⌥ or ⌃ (F1–F12 excepted), so a single key can't take over your keyboard.
- The shortcut recorder cancels on click, recovers if macOS times it out, and beeps when Accessibility permission is missing.
- Permission alerts now explain what to do when the app shows as allowed but isn't working.

## Build from source

> [!IMPORTANT]
> Don't have the original app installed at the same time. Both use the same name and settings and fight over the same shortcuts and swipes.

Clone this repo, then:

```sh
./dist/make-dev-cert.sh   # once: keeps the Accessibility permission across rebuilds
./dist/build.sh --install # builds, replaces /Applications/InstantSpaceSwitcher.app, relaunches
```

## Switching between the original and this fork

**Original → this fork**

1. Quit the original. If you installed it with Homebrew, run `brew uninstall --cask instant-space-switcher`. If not, move it to the Trash.
2. Build and install this fork.
3. In System Settings > Privacy & Security > Accessibility, remove InstantSpaceSwitcher with −, relaunch it, and allow it when asked.

**This fork → original**

1. Quit the app and move it to the Trash.
2. Install the original. On first launch it resets its Accessibility permission and asks again, so allow it.
3. Optional: delete the "InstantSpaceSwitcher Dev" certificate.

## License

Same as the original. See [LICENSE](LICENSE).
