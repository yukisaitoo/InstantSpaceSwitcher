# InstantSpaceSwitcher (fork)

Switch macOS spaces instantly, with no sliding animation.

This is a personal fork of [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) by jurplel. It's trimmed down to left/right switching and has bug fixes I didn't want to wait on.

## Features

- **Keyboard shortcuts**: switch one desktop space left or right. Default binding is ⌃⌥⌘← / ⌃⌥⌘→ (I personally remapped to ⌃← / ⌃→).
- **Trackpad swipe override**: your normal swipe between desktop spaces becomes instant. Speed is adjustable.
- **On-screen display (optional)**: a space number briefly appears when you switch.
- **Menu bar icon (optional)**: shows the current desktop space number.
- **Launch at login (optional)**
- Doesn't require disabling System Integrity Protection

## Removed

- Jump-to-desktop-space shortcut (space 1–16)
- Jump to "last used desktop space".
- Select desktop space submenu in the menu bar.
- The command-line tool (`ISSCli`).

## Fixes

- The app no longer resets its own Accessibility permission every launch.
- Floating windows (like FaceTime picture-in-picture) no longer get left behind when you switch to the first desktop space.
- Swiping no longer gets stuck if macOS briefly pauses the app mid-swipe.
- Quickly switching at the first or last desktop space no longer jumps the wrong way.
- Shortcuts must include ⌘, ⌥ or ⌃ (F1–F12 excepted), so a single key can't take over your keyboard.
- The shortcut recorder cancels on click, recovers if macOS times it out, and beeps when Accessibility permission is missing.
- Permission alerts now explain what to do when the app shows as allowed but isn't working.

<details>
<summary>Tuning the first-desktop-space switch speed</summary>

Switching to the first desktop space uses a slightly slower gesture (default 160) so floating windows render properly.

If they still get left behind, or the switch doesn't feel instant enough, try another value and relaunch the app. It's never faster than the Animation Speed setting. This has no effect on macOS 27+, which ignores gesture speed.

```sh
defaults write com.interversehq.InstantSpaceSwitcher edgeGestureSpeed -float 140   # try a value
defaults delete com.interversehq.InstantSpaceSwitcher edgeGestureSpeed             # back to default
```

</details>

## Build from source

> [!IMPORTANT]
> Don't have the original app installed at the same time. Both use the same name and settings and fight over the same shortcuts and swipes.

Homebrew and the original repo's Releases install the original app, not this fork. Clone this repo, then:

```sh
./dist/make-dev-cert.sh   # once: keeps the Accessibility permission across rebuilds
./dist/build.sh --install # builds, replaces /Applications/InstantSpaceSwitcher.app, relaunches
```

After the first build, open System Settings > Privacy & Security > Accessibility, remove the app with the − button, and grant it again. You only need to do this once.

## Switching between the original and this fork

**Original → this fork**

1. Quit the original. If you installed it with Homebrew, run `brew uninstall --cask instant-space-switcher`. If not, move it to the Trash.
2. Build and install this fork.
3. In System Settings > Privacy & Security > Accessibility, remove InstantSpaceSwitcher with −, relaunch it, and allow it when asked.

**This fork → original**

1. Quit the app and move it to the Trash.
2. Install the original. On first launch it resets its Accessibility permission and asks again, so allow it.
3. Optional: delete the "InstantSpaceSwitcher Dev" certificate in Keychain Access (login keychain).

## License

Same as the original. See [LICENSE](LICENSE).
