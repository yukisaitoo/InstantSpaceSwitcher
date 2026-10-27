import Carbon
@testable import InstantSpaceSwitcher
import XCTest

final class HotkeyCombinationTests: XCTestCase {
  private func shortcut(_ modifiers: Int, key: Int = kVK_ANSI_1, label: String = "1") -> HotkeyCombination {
    HotkeyCombination(keyCode: UInt32(key), modifiers: UInt32(modifiers), displayKey: label)
  }

  func testConflictIgnoresLabels() {
    XCTAssertTrue(shortcut(cmdKey).conflicts(with: shortcut(cmdKey, label: "&")))
  }

  func testDifferentModifiersDoNotConflict() {
    XCTAssertFalse(shortcut(cmdKey).conflicts(with: shortcut(cmdKey | controlKey)))
  }

  func testOptionOnlyShortcutsAreInvalid() {
    XCTAssertFalse(shortcut(optionKey).isValid)
    XCTAssertFalse(shortcut(optionKey | shiftKey).isValid)
    XCTAssertTrue(shortcut(optionKey | controlKey).isValid)
  }

  func testBareFunctionKeyIsValid() {
    XCTAssertTrue(shortcut(0, key: kVK_F5, label: "F5").isValid)
    XCTAssertFalse(shortcut(0).isValid)
  }

  func testDisplayString() {
    XCTAssertEqual(HotkeyCombination.defaultLeft.displayString, "⌃⌥⌘←")
  }

  func testShortcutSavedByOlderVersionsStillDecodes() throws {
    let json = """
      {
        "keyCode": \(kVK_ANSI_1),
        "modifiers": \(cmdKey),
        "displayKey": "1",
        "keyEquivalent": "1",
        "optionKeyKind": "right"
      }
      """

    let decoded = try JSONDecoder().decode(HotkeyCombination.self, from: Data(json.utf8))

    XCTAssertEqual(decoded, shortcut(cmdKey))
  }

  func testHotkeyCanBeSavedAndLoaded() {
    withTemporaryDefaults { defaults in
      let combination = shortcut(cmdKey, key: kVK_ANSI_A, label: "A")
      HotkeyStore(defaults: defaults).update(combination, for: .right)

      XCTAssertEqual(HotkeyStore(defaults: defaults).combination(for: .right), combination)
    }
  }

  func testResetRemovesOverrides() {
    withTemporaryDefaults { defaults in
      let store = HotkeyStore(defaults: defaults)
      store.update(shortcut(cmdKey), for: .left)
      store.setEnabled(false, for: .right)

      store.resetToDefaults()

      XCTAssertEqual(store.combination(for: .left), .defaultLeft)
      XCTAssertTrue(store.isEnabled(.right))
      XCTAssertTrue(defaults.persistentDomain(forName: suiteName)?.isEmpty ?? true)
    }
  }

  private var suiteName: String { "HotkeyStoreTests.\(name)" }

  private func withTemporaryDefaults(_ body: (UserDefaults) -> Void) {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    body(defaults)
  }
}
