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
  var optionKeyKind: OptionKeyKind

  init(
    keyCode: UInt32, modifiers: UInt32, displayKey: String, keyEquivalent: String,
    optionKeyKind: OptionKeyKind = .any
  ) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.displayKey = displayKey
    self.keyEquivalent = keyEquivalent
    self.optionKeyKind = optionKeyKind
  }

  var displayString: String {
    let modifierSymbols = HotkeyCombination.symbols(for: modifiers, optionKeyKind: optionKeyKind)
    return modifierSymbols + displayKey
  }

  var cocoaModifierFlags: NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
    if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
    if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
    if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
    return flags
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
    UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
  ]

  var registrationModifiers: UInt32 {
    modifiers
  }

  func matches(eventModifierFlags flags: UInt64) -> Bool {
    guard modifiers == HotkeyModifierState.carbonMask(fromRawFlags: flags) else {
      return false
    }

    if optionKeyKind == .right {
      return HotkeyModifierState.isRightOptionPressed(rawFlags: flags)
    }

    if modifiers & UInt32(optionKey) != 0 {
      return !HotkeyModifierState.isRightOptionPressed(rawFlags: flags)
    }

    return true
  }

  enum CodingKeys: String, CodingKey {
    case keyCode
    case modifiers
    case displayKey
    case keyEquivalent
    case optionKeyKind
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    keyCode = try container.decode(UInt32.self, forKey: .keyCode)
    modifiers = try container.decode(UInt32.self, forKey: .modifiers)
    displayKey = try container.decode(String.self, forKey: .displayKey)
    keyEquivalent = try container.decode(String.self, forKey: .keyEquivalent)
    optionKeyKind = try container.decodeIfPresent(OptionKeyKind.self, forKey: .optionKeyKind) ?? .any
  }

  static let defaultLeft = HotkeyCombination(
    keyCode: UInt32(kVK_LeftArrow),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "←",
    keyEquivalent: HotkeyCombination.arrowKeyEquivalent(.leftArrow)
  )

  static let defaultRight = HotkeyCombination(
    keyCode: UInt32(kVK_RightArrow),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "→",
    keyEquivalent: HotkeyCombination.arrowKeyEquivalent(.rightArrow)
  )

  static func from(event: NSEvent) -> HotkeyCombination? {
    let modifiers = event.modifierFlags.carbonMask
    let keyCode = UInt32(event.keyCode)
    let optionKeyKind = HotkeyModifierState.optionKeyKind(
      fromRawFlags: UInt64(event.modifierFlags.rawValue))
    
    // Handle arrow keys
    if let special = event.specialKey, let symbol = arrowSymbol(for: special) {
      return HotkeyCombination(
        keyCode: keyCode,
        modifiers: modifiers,
        displayKey: symbol,
        keyEquivalent: arrowKeyEquivalent(special),
        optionKeyKind: optionKeyKind
      )
    }
    
    // Handle special keys (Enter, F-keys, etc.)
    if let (displayKey, keyEquiv) = specialKeyInfo(for: Int(event.keyCode)) {
      return HotkeyCombination(
        keyCode: keyCode,
        modifiers: modifiers,
        displayKey: displayKey,
        keyEquivalent: keyEquiv,
        optionKeyKind: optionKeyKind
      )
    }

    guard let characters = event.charactersIgnoringModifiers, let first = characters.first,
          first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol else {
      return nil
    }

    let upper = String(first).uppercased()
    return HotkeyCombination(
      keyCode: keyCode,
      modifiers: modifiers,
      displayKey: upper,
      keyEquivalent: String(first).lowercased(),
      optionKeyKind: optionKeyKind
    )
  }

  static func arrowSymbol(for specialKey: NSEvent.SpecialKey) -> String? {
    switch specialKey {
    case .leftArrow: return "←"
    case .rightArrow: return "→"
    case .upArrow: return "↑"
    case .downArrow: return "↓"
    default: return nil
    }
  }
  
  private static func specialKeyInfo(for keyCode: Int) -> (displayKey: String, keyEquivalent: String)? {
    switch keyCode {
    // Enter/Return
    case kVK_Return:
      return ("↩", String(Character(UnicodeScalar(NSCarriageReturnCharacter)!)))
    case kVK_ANSI_KeypadEnter:
      return ("⌅", String(Character(UnicodeScalar(NSEnterCharacter)!)))
    // Tab
    case kVK_Tab:
      return ("⇥", String(Character(UnicodeScalar(NSTabCharacter)!)))
    // Delete/Backspace
    case kVK_Delete:
      return ("⌫", String(Character(UnicodeScalar(NSBackspaceCharacter)!)))
    case kVK_ForwardDelete:
      return ("⌦", String(Character(UnicodeScalar(NSDeleteCharacter)!)))
    // Space
    case kVK_Space:
      return ("Space", " ")
    // F-keys
    case kVK_F1:
      return ("F1", String(Character(UnicodeScalar(NSF1FunctionKey)!)))
    case kVK_F2:
      return ("F2", String(Character(UnicodeScalar(NSF2FunctionKey)!)))
    case kVK_F3:
      return ("F3", String(Character(UnicodeScalar(NSF3FunctionKey)!)))
    case kVK_F4:
      return ("F4", String(Character(UnicodeScalar(NSF4FunctionKey)!)))
    case kVK_F5:
      return ("F5", String(Character(UnicodeScalar(NSF5FunctionKey)!)))
    case kVK_F6:
      return ("F6", String(Character(UnicodeScalar(NSF6FunctionKey)!)))
    case kVK_F7:
      return ("F7", String(Character(UnicodeScalar(NSF7FunctionKey)!)))
    case kVK_F8:
      return ("F8", String(Character(UnicodeScalar(NSF8FunctionKey)!)))
    case kVK_F9:
      return ("F9", String(Character(UnicodeScalar(NSF9FunctionKey)!)))
    case kVK_F10:
      return ("F10", String(Character(UnicodeScalar(NSF10FunctionKey)!)))
    case kVK_F11:
      return ("F11", String(Character(UnicodeScalar(NSF11FunctionKey)!)))
    case kVK_F12:
      return ("F12", String(Character(UnicodeScalar(NSF12FunctionKey)!)))
    // Home/End/Page
    case kVK_Home:
      return ("↖", String(Character(UnicodeScalar(NSHomeFunctionKey)!)))
    case kVK_End:
      return ("↘", String(Character(UnicodeScalar(NSEndFunctionKey)!)))
    case kVK_PageUp:
      return ("⇞", String(Character(UnicodeScalar(NSPageUpFunctionKey)!)))
    case kVK_PageDown:
      return ("⇟", String(Character(UnicodeScalar(NSPageDownFunctionKey)!)))
    default:
      return nil
    }
  }

  private static func arrowKeyEquivalent(_ specialKey: NSEvent.SpecialKey) -> String {
    switch specialKey {
    case .leftArrow:
      return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
    case .rightArrow:
      return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
    case .upArrow:
      return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    case .downArrow:
      return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
    default:
      return ""
    }
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

enum HotkeyModifierState {
  private static let deviceRightOptionMask: UInt64 = 0x00000040

  static func optionKeyKind(fromRawFlags flags: UInt64) -> OptionKeyKind {
    isRightOptionPressed(rawFlags: flags) ? .right : .any
  }

  static func isRightOptionPressed(rawFlags flags: UInt64) -> Bool {
    flags & deviceRightOptionMask != 0
  }

  static func carbonMask(fromRawFlags flags: UInt64) -> UInt32 {
    NSEvent.ModifierFlags(rawValue: UInt(flags)).carbonMask
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
}

final class HotkeyStore: ObservableObject {
  static let shared = HotkeyStore()

  @Published private(set) var leftHotkey: HotkeyCombination
  @Published private(set) var rightHotkey: HotkeyCombination
  @Published private(set) var enabledStates: [HotkeyIdentifier: Bool] = [:]

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    leftHotkey = defaults.hotkey(forKey: DefaultsKey.left.rawValue) ?? .defaultLeft
    rightHotkey = defaults.hotkey(forKey: DefaultsKey.right.rawValue) ?? .defaultRight

    for identifier in HotkeyIdentifier.allCases {
      let key = "enabled.\(identifier.rawValue)"
      enabledStates[identifier] = defaults.object(forKey: key) as? Bool ?? true
    }
  }

  func update(_ combination: HotkeyCombination, for identifier: HotkeyIdentifier) {
    switch identifier {
    case .left:
      guard combination != leftHotkey else { return }
      leftHotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.left.rawValue)
    case .right:
      guard combination != rightHotkey else { return }
      rightHotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.right.rawValue)
    }
  }

  func resetToDefaults() {
    leftHotkey = .defaultLeft
    rightHotkey = .defaultRight

    defaults.setHotkey(leftHotkey, forKey: DefaultsKey.left.rawValue)
    defaults.setHotkey(rightHotkey, forKey: DefaultsKey.right.rawValue)
  }

  func combination(for identifier: HotkeyIdentifier) -> HotkeyCombination {
    switch identifier {
    case .left: return leftHotkey
    case .right: return rightHotkey
    }
  }

  func isEnabled(_ identifier: HotkeyIdentifier) -> Bool {
    return enabledStates[identifier] ?? true
  }

  func setEnabled(_ enabled: Bool, for identifier: HotkeyIdentifier) {
    enabledStates[identifier] = enabled
    let key = "enabled.\(identifier.rawValue)"
    defaults.set(enabled, forKey: key)
  }

  private enum DefaultsKey: String {
    case left = "hotkey.left"
    case right = "hotkey.right"
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
