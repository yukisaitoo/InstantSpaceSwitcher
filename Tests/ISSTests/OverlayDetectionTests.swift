import ISS
import XCTest

// Tests the App Exposé / Mission Control heuristic in ISS.c against window lists
// shaped like CGWindowListCopyWindowInfo output. The window counts come from real
// captures on macOS 26.2 with one and two displays. The C functions aren't in
// ISS.h, so they're bound by name.

@_silgen_name("iss_is_expose_detected_in_window_list")
private func iss_is_expose_detected_in_window_list(_ windowList: CFArray) -> Bool

@_silgen_name("iss_is_mission_control_detected_in_window_list")
private func iss_is_mission_control_detected_in_window_list(_ windowList: CFArray) -> Bool

/// The layer of the Dock's always-present desktop windows, one per display.
private let wallpaperLayer = -2147483624

final class OverlayDetectionTests: XCTestCase {
  private func dockWindows(layer20: Int = 0, layer18: Int = 0, wallpaper: Int = 0) -> [NSDictionary] {
    let layers =
      Array(repeating: 20, count: layer20) + Array(repeating: 18, count: layer18)
      + Array(repeating: wallpaperLayer, count: wallpaper)
    return layers.map { ["kCGWindowOwnerName": "Dock", "kCGWindowLayer": NSNumber(value: $0)] }
  }

  private func assertDetects(
    _ windows: [NSDictionary], expose: Bool, missionControl: Bool,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let list = windows as NSArray as CFArray
    XCTAssertEqual(iss_is_expose_detected_in_window_list(list), expose, "App Exposé", file: file, line: line)
    XCTAssertEqual(
      iss_is_mission_control_detected_in_window_list(list), missionControl, "Mission Control", file: file, line: line)
  }

  func testNormalStateIsNeither() {
    assertDetects(dockWindows(wallpaper: 2), expose: false, missionControl: false)
    assertDetects(dockWindows(wallpaper: 1), expose: false, missionControl: false)
  }

  func testAppExpose() {
    assertDetects(dockWindows(layer20: 2, layer18: 2, wallpaper: 2), expose: true, missionControl: false)
    assertDetects(dockWindows(layer20: 1, layer18: 2, wallpaper: 2), expose: true, missionControl: false)
  }

  func testSingleDisplayAppExpose() {
    assertDetects(dockWindows(layer20: 1, layer18: 1, wallpaper: 1), expose: true, missionControl: false)
  }

  func testMissionControl() {
    assertDetects(dockWindows(layer20: 3, layer18: 2, wallpaper: 2), expose: false, missionControl: true)
  }

  func testSingleDisplayMissionControl() {
    assertDetects(dockWindows(layer20: 2, layer18: 1, wallpaper: 1), expose: false, missionControl: true)
    assertDetects(dockWindows(layer20: 3, layer18: 1), expose: false, missionControl: true)
    assertDetects(dockWindows(layer20: 5, layer18: 1), expose: false, missionControl: true)
  }

  func testEmptyListIsNeither() {
    assertDetects([], expose: false, missionControl: false)
  }

  func testNonDockWindowsAreIgnored() {
    let windows: [NSDictionary] = [18, 20].map {
      ["kCGWindowOwnerName": "WindowServer", "kCGWindowLayer": NSNumber(value: $0)]
    }
    assertDetects(windows, expose: false, missionControl: false)
  }

  func testLayer18AloneIsNeither() {
    assertDetects(dockWindows(layer18: 1), expose: false, missionControl: false)
  }

  func testLayer20WithoutLayer18IsNeither() {
    assertDetects(dockWindows(layer20: 1), expose: false, missionControl: false)
    assertDetects(dockWindows(layer20: 2), expose: false, missionControl: false)
  }
}
