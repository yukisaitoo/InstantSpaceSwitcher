import Foundation

enum Settings {
  private static var defaults: UserDefaults { .standard }

  static var swipeOverride: Bool {
    get { defaults.bool(forKey: "swipeOverride") }
    set { defaults.set(newValue, forKey: "swipeOverride") }
  }

  static var overlayDetectionEnabled: Bool {
    get { defaults.object(forKey: "overlayDetectionEnabled") as? Bool ?? true }
    set { defaults.set(newValue, forKey: "overlayDetectionEnabled") }
  }

  static var showOSD: Bool {
    get { defaults.bool(forKey: "showOSD") }
    set { defaults.set(newValue, forKey: "showOSD") }
  }

  static var osdDurationMs: Int {
    get { defaults.object(forKey: "osdDurationMs") as? Int ?? 500 }
    set { defaults.set(newValue, forKey: "osdDurationMs") }
  }

  static var showOSDInMissionControl: Bool {
    get { defaults.bool(forKey: "showOSDInMissionControl") }
    set { defaults.set(newValue, forKey: "showOSDInMissionControl") }
  }
}
