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
- Shortcuts specific to the right Option key (AltGr).
- Per-shortcut reset buttons. "Reset All to Defaults" remains.

## Fixes

- The app no longer resets its own Accessibility permission every launch.
- Swiping no longer gets stuck if macOS briefly pauses the app mid-swipe.
- Quickly switching at the first or last desktop space no longer jumps the wrong way.
- Shortcuts must include ⌘ or ⌃ (F1–F12 excepted), so a single key can't take over your keyboard. macOS no longer allows ⌥-only shortcuts.
- Shortcuts use macOS's standard hotkey API, so the app no longer sees what you type.
- The shortcut recorder cancels on click or Esc, and only listens inside the Settings window.
- "Reset All to Defaults" clears your saved shortcuts instead of copying the defaults over them.
- Permission alerts now explain what to do when the app shows as allowed but isn't working.
- Switching no longer goes the wrong way after closing Mission Control; swipes made while it is still closing are ignored.
- Switching can no longer overshoot into an empty black space past the first or last desktop space.
- One switch per key press: holding a shortcut switches once, and nothing happens (no beep) at the first or last space.

## A shortcut makes an alert sound

Another app uses the same keys and couldn't do anything with them. For example, Rectangle's Next/Previous Display default to ⌃⌥⌘→ / ⌃⌥⌘←. Clear or change the shortcut in that app.

## FaceTime call window disappearing (testing)

Switching to the first desktop space can hide FaceTime's floating call window until the next animation. The switch speed into the first space is tunable while this is being tested. Lower is gentler, but too low may stop the switch from landing. It's read on every switch, so there's no need to relaunch.

```sh
defaults write com.interversehq.InstantSpaceSwitcher firstSpaceFlingVelocity -float 500   # try 2000, 500, 160, 50
defaults delete com.interversehq.InstantSpaceSwitcher firstSpaceFlingVelocity            # back to the default (9999)
```

To watch what the app is doing (in zsh, `log` alone is a different built-in command):

```sh
/usr/bin/log stream --level debug --predicate 'subsystem == "com.interversehq.InstantSpaceSwitcher"'
```

## Build from source

> [!IMPORTANT]
> Don't have the original app installed at the same time. Both use the same name and settings and fight over the same shortcuts and swipes.

Clone this repo, then:

```sh
./dist/make-dev-cert.sh   # once: keeps the Accessibility permission across rebuilds
./dist/build.sh           # builds, replaces /Applications/InstantSpaceSwitcher.app, relaunches
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
