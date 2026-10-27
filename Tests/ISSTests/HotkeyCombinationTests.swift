import AppKit
import Carbon
@testable import InstantSpaceSwitcher
import XCTest

final class HotkeyCombinationTests: XCTestCase {
  private let optionFlags = UInt64(NSEvent.ModifierFlags.option.rawValue)
  private let controlOptionFlags = UInt64(NSEvent.ModifierFlags([.control, .option]).rawValue)
  private let rightOptionFlags = UInt64(NSEvent.ModifierFlags.option.rawValue) | 0x40  // NX_DEVICERALTKEYMASK

  private func optionOne(_ optionKeyKind: OptionKeyKind = .any) -> HotkeyCombination {
    HotkeyCombination(
      keyCode: UInt32(kVK_ANSI_1),
      modifiers: UInt32(optionKey),
      displayKey: "1",
      keyEquivalent: "1",
      optionKeyKind: optionKeyKind
    )
  }

  func testGenericOptionDoesNotMatchAdditionalControl() {
    XCTAssertTrue(optionOne().matches(eventModifierFlags: optionFlags))
    XCTAssertFalse(optionOne().matches(eventModifierFlags: controlOptionFlags))
  }

  func testGenericOptionDoesNotMatchRightOption() {
    XCTAssertFalse(optionOne().matches(eventModifierFlags: rightOptionFlags))
  }

  func testConflictIgnoresLabels() {
    var relabeled = optionOne()
    relabeled.displayKey = "&"
    relabeled.keyEquivalent = "&"
    XCTAssertTrue(optionOne().conflicts(with: relabeled))
  }

  func testOptionAndAltGrDoNotConflict() {
    XCTAssertFalse(optionOne().conflicts(with: optionOne(.right)))
  }

  func testDifferentModifiersDoNotConflict() {
    var withControl = optionOne()
    withControl.modifiers |= UInt32(controlKey)
    XCTAssertFalse(optionOne().conflicts(with: withControl))
  }

  func testAltGrRequiresRightOption() {
    XCTAssertFalse(optionOne(.right).matches(eventModifierFlags: optionFlags))
    XCTAssertTrue(optionOne(.right).matches(eventModifierFlags: rightOptionFlags))
  }

  func testLegacyDecodedShortcutDefaultsToGenericOption() throws {
    let json = """
      {
        "keyCode": \(kVK_ANSI_1),
        "modifiers": \(optionKey),
        "displayKey": "1",
        "keyEquivalent": "1"
      }
      """

    let decoded = try JSONDecoder().decode(HotkeyCombination.self, from: Data(json.utf8))

    XCTAssertEqual(decoded.optionKeyKind, .any)
    XCTAssertFalse(decoded.matches(eventModifierFlags: rightOptionFlags))
  }

  func testAltGrDisplayIsDistinctFromGenericOption() {
    XCTAssertEqual(optionOne().displayString, "⌥1")
    XCTAssertEqual(optionOne(.right).displayString, "AltGr1")
    XCTAssertNotEqual(optionOne(), optionOne(.right))
  }

  func testAltGrSpecificShortcutWinsOverGenericOption() {
    XCTAssertEqual(
      HotkeyManager.preferredCombination(
        from: [optionOne(), optionOne(.right)],
        keyCode: UInt32(kVK_ANSI_1),
        eventModifierFlags: rightOptionFlags),
      optionOne(.right)
    )
  }

  func testNoShortcutSelectedForWrongKeyCode() {
    XCTAssertNil(
      HotkeyManager.preferredCombination(
        from: [optionOne()],
        keyCode: UInt32(kVK_ANSI_2),
        eventModifierFlags: optionFlags)
    )
  }

  func testHotkeyCanBeSavedAndLoaded() {
    let suiteName = "HotkeyStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let combination = HotkeyCombination(
      keyCode: UInt32(kVK_ANSI_A),
      modifiers: UInt32(cmdKey),
      displayKey: "A",
      keyEquivalent: "a"
    )
    HotkeyStore(defaults: defaults).update(combination, for: .right)

    XCTAssertEqual(HotkeyStore(defaults: defaults).combination(for: .right), combination)
  }
}
