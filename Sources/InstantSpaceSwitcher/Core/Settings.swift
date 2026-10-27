import Foundation

enum Settings {
  private enum Key {
    static let swipeOverride = "swipeOverride"
    static let overlayDetectionEnabled = "overlayDetectionEnabled"
    static let showOSD = "showOSD"
    static let osdDurationMs = "osdDurationMs"
    static let showOSDInMissionControl = "showOSDInMissionControl"
  }

  static let defaultOSDDurationMs = 500

  private static var defaults: UserDefaults { .standard }

  static var swipeOverride: Bool {
    get { defaults.bool(forKey: Key.swipeOverride) }
    set { defaults.set(newValue, forKey: Key.swipeOverride) }
  }

  static var overlayDetectionEnabled: Bool {
    get { defaults.object(forKey: Key.overlayDetectionEnabled) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Key.overlayDetectionEnabled) }
  }

  static var showOSD: Bool {
    get { defaults.bool(forKey: Key.showOSD) }
    set { defaults.set(newValue, forKey: Key.showOSD) }
  }

  static var osdDurationMs: Int {
    get { defaults.object(forKey: Key.osdDurationMs) as? Int ?? defaultOSDDurationMs }
    set { defaults.set(newValue, forKey: Key.osdDurationMs) }
  }

  static var showOSDInMissionControl: Bool {
    get { defaults.bool(forKey: Key.showOSDInMissionControl) }
    set { defaults.set(newValue, forKey: Key.showOSDInMissionControl) }
  }
}
