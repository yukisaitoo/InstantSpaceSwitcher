import AppKit
import Carbon

struct HotkeyCombination: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32

  @MainActor var displayString: String {
    HotkeyCombination.symbols(for: modifiers) + (keyLabel ?? "Key \(keyCode)")
  }

  /// The key's name in the current keyboard layout, or nil if it has none.
  @MainActor var keyLabel: String? {
    if let name = HotkeyCombination.namedKeys[Int(keyCode)] {
      return name
    }
    guard let character = HotkeyCombination.character(forKeyCode: keyCode) else { return nil }
    // Keycap style keeps keypad keys apart from the main row
    return HotkeyCombination.keypadKeyCodes.contains(Int(keyCode)) ? character + "\u{20E3}" : character.uppercased()
  }

  @MainActor var isValid: Bool {
    guard keyLabel != nil else { return false }
    if HotkeyCombination.bareAllowedKeyCodes.contains(keyCode) { return true }
    // Without ⌘ or ⌃ the shortcut would take a keystroke people type with,
    // like ⇧A or ⌥E for é, away from every app.
    let required = UInt32(cmdKey) | UInt32(controlKey)
    return modifiers & required != 0
  }

  /// Whether an enabled macOS shortcut (System Settings › Keyboard › Keyboard Shortcuts) uses the same keys.
  var isTakenBySystem: Bool {
    HotkeyCombination.systemShortcuts().contains(self)
  }

  static let defaultLeft = HotkeyCombination(keyCode: UInt32(kVK_LeftArrow), modifiers: defaultModifierMask)
  static let defaultRight = HotkeyCombination(keyCode: UInt32(kVK_RightArrow), modifiers: defaultModifierMask)

  init(keyCode: UInt32, modifiers: UInt32) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  init(event: NSEvent) {
    self.init(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags.carbonMask)
  }

  static func systemShortcuts() -> [HotkeyCombination] {
    var unmanaged: Unmanaged<CFArray>?
    guard CopySymbolicHotKeys(&unmanaged) == noErr,
          let entries = unmanaged?.takeRetainedValue() as? [[String: Any]] else {
      return []
    }
    return entries.compactMap { entry in
      guard entry[kHISymbolicHotKeyEnabled] as? Bool == true,
            let keyCode = entry[kHISymbolicHotKeyCode] as? Int,
            let modifiers = entry[kHISymbolicHotKeyModifiers] as? Int else {
        return nil
      }
      return systemShortcut(keyCode: keyCode, modifiers: modifiers)
    }
  }

  /// macOS reports arrow, function and navigation keys with the Fn flag set, which our shortcuts never carry.
  static func systemShortcut(keyCode: Int, modifiers: Int) -> HotkeyCombination {
    let compared = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey) | UInt32(shiftKey)
    return HotkeyCombination(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers) & compared)
  }

  // TISGetInputSourceProperty crashes off the main thread
  @MainActor private static func character(forKeyCode keyCode: UInt32) -> String? {
    guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
          let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
      return nil
    }
    let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue()
    let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)

    var deadKeyState: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)
    let status = UCKeyTranslate(
      layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
      OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
    )
    guard status == noErr else { return nil }

    let string = String(utf16CodeUnits: characters, count: length)
    guard string.count == 1, let first = string.first,
          first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol else {
      return nil
    }
    return string
  }

  private static let bareAllowedKeyCodes: Set<UInt32> = [
    UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
    UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
    UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12)
  ]

  private static let namedKeys: [Int: String] = [
    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌅", kVK_Tab: "⇥", kVK_Space: "Space",
    kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_ANSI_KeypadClear: "⌧",
    kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
    kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
    kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
  ]

  private static let keypadKeyCodes: Set<Int> = [
    kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
    kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
    kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadDivide,
    kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadEquals
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
