import AppKit
import Carbon

final class HotkeyManager {
  static let shared = HotkeyManager()

  private struct Entry {
    let combination: HotkeyCombination
    let handler: () -> Void
  }

  private var entries: [HotkeyIdentifier: Entry] = [:]
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var retryScheduled = false

  private init() {
    installEventTap()
  }

  func register(
    identifier: HotkeyIdentifier, combination: HotkeyCombination, handler: @escaping () -> Void
  ) {
    entries[identifier] = Entry(combination: combination, handler: handler)
    installEventTap()
  }

  func unregister(identifier: HotkeyIdentifier) {
    entries.removeValue(forKey: identifier)
  }

  func unregisterAll() {
    entries.removeAll()
  }

  private func installEventTap() {
    if let eventTap {
      if CFMachPortIsValid(eventTap) {
        return
      }
      self.eventTap = nil
      runLoopSource = nil
    }

    let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: { _, type, event, userInfo in
          guard let userInfo else { return Unmanaged.passUnretained(event) }
          let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

          if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = manager.eventTap {
              CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
          }

          guard type == .keyDown, manager.dispatch(event: event) else {
            return Unmanaged.passUnretained(event)
          }
          return nil
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      print("Failed to install hotkey event tap")
      scheduleEventTapRetry()
      return
    }

    self.eventTap = eventTap
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    if let runLoopSource {
      CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  private func scheduleEventTapRetry() {
    guard !retryScheduled else { return }
    retryScheduled = true

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self else { return }
      self.retryScheduled = false
      self.installEventTap()
    }
  }

  private func dispatch(event: CGEvent) -> Bool {
    let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
    guard
      let combination = Self.preferredCombination(
        from: entries.values.map(\.combination), keyCode: keyCode, eventModifierFlags: event.flags.rawValue),
      let entry = entries.values.first(where: { $0.combination == combination })
    else {
      return false
    }

    // One switch per press; a held key's repeats are swallowed so they don't reach the focused app
    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
      DispatchQueue.main.async(execute: entry.handler)
    }
    return true
  }

  /// The combination matching the key event, preferring AltGr-specific shortcuts
  /// over generic Option ones.
  static func preferredCombination(
    from combinations: [HotkeyCombination], keyCode: UInt32, eventModifierFlags flags: UInt64
  ) -> HotkeyCombination? {
    combinations.filter {
      $0.keyCode == keyCode && $0.matches(eventModifierFlags: flags)
    }.max {
      priority(for: $0) < priority(for: $1)
    }
  }

  private static func priority(for combination: HotkeyCombination) -> Int {
    combination.optionKeyKind == .right ? 1 : 0
  }
}
