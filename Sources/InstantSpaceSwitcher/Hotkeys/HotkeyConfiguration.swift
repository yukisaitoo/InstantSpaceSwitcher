import AppKit
import Carbon

struct HotkeyCombination: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  var displayKey: String

  var displayString: String {
    HotkeyCombination.symbols(for: modifiers) + displayKey
  }

  var isValid: Bool {
    guard !displayKey.isEmpty else { return false }
    if HotkeyCombination.bareAllowedKeyCodes.contains(keyCode) { return true }
    // A printable key without ⌘ or ⌃ would be swallowed system-wide, making it
    // unusable for typing, and macOS refuses ⌥- and ⌥⇧-only hotkeys anyway.
    let required = UInt32(cmdKey) | UInt32(controlKey)
    return modifiers & required != 0
  }

  private static let bareAllowedKeyCodes: Set<UInt32> = [
    UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
    UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
    UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12)
  ]

  /// Whether both fire on the same key press. Labels are ignored: the same key
  /// recorded under another keyboard layout gets a different one.
  func conflicts(with other: HotkeyCombination) -> Bool {
    keyCode == other.keyCode && modifiers == other.modifiers
  }

  static let defaultLeft = HotkeyCombination(
    keyCode: UInt32(kVK_LeftArrow), modifiers: defaultModifierMask, displayKey: "←"
  )

  static let defaultRight = HotkeyCombination(
    keyCode: UInt32(kVK_RightArrow), modifiers: defaultModifierMask, displayKey: "→"
  )

  static func from(event: NSEvent) -> HotkeyCombination? {
    guard let displayKey = displayKey(for: event) else { return nil }
    return HotkeyCombination(
      keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags.carbonMask, displayKey: displayKey
    )
  }

  private static func displayKey(for event: NSEvent) -> String? {
    if let name = namedKeys[Int(event.keyCode)] {
      return name
    }
    guard let first = event.charactersIgnoringModifiers?.first,
          first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol else {
      return nil
    }
    return String(first).uppercased()
  }

  private static let namedKeys: [Int: String] = [
    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌅", kVK_Tab: "⇥", kVK_Space: "Space",
    kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
    kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
    kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
  ]

  private static func symbols(for modifiers: UInt32) -> String {
    var result = ""
    if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
    return result
  }

  private static let defaultModifierMask = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
}

enum HotkeyIdentifier: String, CaseIterable {
  case left
  case right

  var displayName: String {
    switch self {
    case .left: return "Switch to space on the left"
    case .right: return "Switch to space on the right"
    }
  }

  var defaultCombination: HotkeyCombination {
    switch self {
    case .left: return .defaultLeft
    case .right: return .defaultRight
    }
  }

  fileprivate var defaultsKey: String { "hotkey.\(rawValue)" }
  fileprivate var enabledDefaultsKey: String { "enabled.\(rawValue)" }
}

final class HotkeyStore: ObservableObject {
  static let shared = HotkeyStore()

  @Published private(set) var hotkeys: [HotkeyIdentifier: HotkeyCombination] = [:]
  @Published private(set) var enabledStates: [HotkeyIdentifier: Bool] = [:]

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    load()
  }

  func combination(for identifier: HotkeyIdentifier) -> HotkeyCombination {
    hotkeys[identifier] ?? identifier.defaultCombination
  }

  func update(_ combination: HotkeyCombination, for identifier: HotkeyIdentifier) {
    guard combination != hotkeys[identifier] else { return }
    hotkeys[identifier] = combination
    defaults.setHotkey(combination, forKey: identifier.defaultsKey)
  }

  /// Removes the saved values instead of writing the defaults, so a later
  /// version's defaults apply.
  func resetToDefaults() {
    for identifier in HotkeyIdentifier.allCases {
      defaults.removeObject(forKey: identifier.defaultsKey)
      defaults.removeObject(forKey: identifier.enabledDefaultsKey)
    }
    load()
  }

  func isEnabled(_ identifier: HotkeyIdentifier) -> Bool {
    enabledStates[identifier] ?? true
  }

  func setEnabled(_ enabled: Bool, for identifier: HotkeyIdentifier) {
    enabledStates[identifier] = enabled
    defaults.set(enabled, forKey: identifier.enabledDefaultsKey)
  }

  private func load() {
    for identifier in HotkeyIdentifier.allCases {
      hotkeys[identifier] = defaults.hotkey(forKey: identifier.defaultsKey) ?? identifier.defaultCombination
      enabledStates[identifier] = defaults.object(forKey: identifier.enabledDefaultsKey) as? Bool ?? true
    }
  }
}

extension UserDefaults {
  fileprivate func hotkey(forKey key: String) -> HotkeyCombination? {
    guard let data = data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(HotkeyCombination.self, from: data)
  }

  fileprivate func setHotkey(_ hotkey: HotkeyCombination, forKey key: String) {
    if let data = try? JSONEncoder().encode(hotkey) {
      set(data, forKey: key)
    }
  }
}

extension NSEvent.ModifierFlags {
  var carbonMask: UInt32 {
    var mask: UInt32 = 0
    if contains(.command) { mask |= UInt32(cmdKey) }
    if contains(.option) { mask |= UInt32(optionKey) }
    if contains(.control) { mask |= UInt32(controlKey) }
    if contains(.shift) { mask |= UInt32(shiftKey) }
    return mask
  }
}
