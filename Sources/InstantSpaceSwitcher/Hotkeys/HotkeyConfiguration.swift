import AppKit
import Carbon
import Foundation

enum OptionKeyKind: String, Codable {
  case any
  case right
}

struct HotkeyCombination: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  var displayKey: String
  var keyEquivalent: String
  var optionKeyKind: OptionKeyKind = .any

  /// NX_DEVICERALTKEYMASK: the device-specific modifier flag for the right Option key.
  private static let rightOptionDeviceFlag: UInt64 = 0x40

  var displayString: String {
    HotkeyCombination.symbols(for: modifiers, optionKeyKind: optionKeyKind) + displayKey
  }

  var isValid: Bool {
    guard !displayKey.isEmpty else { return false }
    if HotkeyCombination.bareAllowedKeyCodes.contains(keyCode) { return true }
    // A printable key without ⌘/⌥/⌃ (shift alone is just typing) would be
    // swallowed system-wide by the hotkey tap, making that key unusable in
    // every app — require a real modifier for anything but function keys.
    let required = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
    return modifiers & required != 0
  }

  private static let bareAllowedKeyCodes: Set<UInt32> = [
    UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
    UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
    UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12)
  ]

  func matches(eventModifierFlags flags: UInt64) -> Bool {
    guard modifiers == NSEvent.ModifierFlags(rawValue: UInt(flags)).carbonMask else {
      return false
    }

    let rightOptionPressed = HotkeyCombination.isRightOptionPressed(flags)
    if optionKeyKind == .right {
      return rightOptionPressed
    }
    if modifiers & UInt32(optionKey) != 0 {
      return !rightOptionPressed
    }
    return true
  }

  /// Whether both fire on the same key press. Labels are ignored: the same key
  /// recorded under another keyboard layout gets a different one.
  func conflicts(with other: HotkeyCombination) -> Bool {
    keyCode == other.keyCode && modifiers == other.modifiers && optionKeyKind == other.optionKeyKind
  }

  static let defaultLeft = HotkeyCombination(
    keyCode: UInt32(kVK_LeftArrow),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "←",
    keyEquivalent: HotkeyCombination.character(NSEvent.SpecialKey.leftArrow.rawValue)
  )

  static let defaultRight = HotkeyCombination(
    keyCode: UInt32(kVK_RightArrow),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "→",
    keyEquivalent: HotkeyCombination.character(NSEvent.SpecialKey.rightArrow.rawValue)
  )

  static func from(event: NSEvent) -> HotkeyCombination? {
    guard let labels = keyLabels(for: event) else { return nil }
    let rawFlags = UInt64(event.modifierFlags.rawValue)
    return HotkeyCombination(
      keyCode: UInt32(event.keyCode),
      modifiers: event.modifierFlags.carbonMask,
      displayKey: labels.displayKey,
      keyEquivalent: labels.keyEquivalent,
      optionKeyKind: isRightOptionPressed(rawFlags) ? .right : .any
    )
  }

  private static func keyLabels(for event: NSEvent) -> (displayKey: String, keyEquivalent: String)? {
    if let special = event.specialKey, let symbol = arrowSymbols[special] {
      return (symbol, character(special.rawValue))
    }
    if let key = specialKeys[Int(event.keyCode)] {
      return (key.displayKey, character(key.character))
    }

    guard let first = event.charactersIgnoringModifiers?.first,
          first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol else {
      return nil
    }
    return (String(first).uppercased(), String(first).lowercased())
  }

  private static let arrowSymbols: [NSEvent.SpecialKey: String] = [
    .leftArrow: "←", .rightArrow: "→", .upArrow: "↑", .downArrow: "↓"
  ]

  private static let specialKeys: [Int: (displayKey: String, character: Int)] = [
    kVK_Return: ("↩", NSCarriageReturnCharacter),
    kVK_ANSI_KeypadEnter: ("⌅", NSEnterCharacter),
    kVK_Tab: ("⇥", NSTabCharacter),
    kVK_Delete: ("⌫", NSBackspaceCharacter),
    kVK_ForwardDelete: ("⌦", NSDeleteCharacter),
    kVK_Space: ("Space", 0x20),
    kVK_F1: ("F1", NSF1FunctionKey),
    kVK_F2: ("F2", NSF2FunctionKey),
    kVK_F3: ("F3", NSF3FunctionKey),
    kVK_F4: ("F4", NSF4FunctionKey),
    kVK_F5: ("F5", NSF5FunctionKey),
    kVK_F6: ("F6", NSF6FunctionKey),
    kVK_F7: ("F7", NSF7FunctionKey),
    kVK_F8: ("F8", NSF8FunctionKey),
    kVK_F9: ("F9", NSF9FunctionKey),
    kVK_F10: ("F10", NSF10FunctionKey),
    kVK_F11: ("F11", NSF11FunctionKey),
    kVK_F12: ("F12", NSF12FunctionKey),
    kVK_Home: ("↖", NSHomeFunctionKey),
    kVK_End: ("↘", NSEndFunctionKey),
    kVK_PageUp: ("⇞", NSPageUpFunctionKey),
    kVK_PageDown: ("⇟", NSPageDownFunctionKey)
  ]

  private static func character(_ code: Int) -> String {
    UnicodeScalar(code).map { String(Character($0)) } ?? ""
  }

  private static func isRightOptionPressed(_ flags: UInt64) -> Bool {
    flags & rightOptionDeviceFlag != 0
  }

  private static func symbols(for modifiers: UInt32, optionKeyKind: OptionKeyKind) -> String {
    var result = ""
    if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
    if modifiers & UInt32(optionKey) != 0 {
      result += optionKeyKind == .right ? "AltGr" : "⌥"
    }
    if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
    return result
  }

  private static var defaultModifierMask: UInt32 {
    UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
  }
}

extension HotkeyCombination {
  // In an extension so the memberwise initializer is still generated.
  // Shortcuts saved before AltGr support have no optionKeyKind.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    keyCode = try container.decode(UInt32.self, forKey: .keyCode)
    modifiers = try container.decode(UInt32.self, forKey: .modifiers)
    displayKey = try container.decode(String.self, forKey: .displayKey)
    keyEquivalent = try container.decode(String.self, forKey: .keyEquivalent)
    optionKeyKind = try container.decodeIfPresent(OptionKeyKind.self, forKey: .optionKeyKind) ?? .any
  }
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
    for identifier in HotkeyIdentifier.allCases {
      hotkeys[identifier] = defaults.hotkey(forKey: identifier.defaultsKey) ?? identifier.defaultCombination
      enabledStates[identifier] = defaults.object(forKey: identifier.enabledDefaultsKey) as? Bool ?? true
    }
  }

  func combination(for identifier: HotkeyIdentifier) -> HotkeyCombination {
    hotkeys[identifier] ?? identifier.defaultCombination
  }

  func update(_ combination: HotkeyCombination, for identifier: HotkeyIdentifier) {
    guard combination != hotkeys[identifier] else { return }
    hotkeys[identifier] = combination
    defaults.setHotkey(combination, forKey: identifier.defaultsKey)
  }

  func resetToDefaults() {
    for identifier in HotkeyIdentifier.allCases {
      hotkeys[identifier] = identifier.defaultCombination
      defaults.setHotkey(identifier.defaultCombination, forKey: identifier.defaultsKey)
    }
  }

  func isEnabled(_ identifier: HotkeyIdentifier) -> Bool {
    enabledStates[identifier] ?? true
  }

  func setEnabled(_ enabled: Bool, for identifier: HotkeyIdentifier) {
    enabledStates[identifier] = enabled
    defaults.set(enabled, forKey: identifier.enabledDefaultsKey)
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
