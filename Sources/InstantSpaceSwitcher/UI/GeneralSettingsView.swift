import ISS
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
  private static let durationPresets = [100, 200, 300, 500, 750, 1000]

  @AppStorage(Settings.Key.swipeOverride) private var swipeOverride = false
  @AppStorage(Settings.Key.overlayDetectionEnabled) private var overlayDetection = Settings.defaultOverlayDetectionEnabled
  @AppStorage(Settings.Key.showOSD) private var showOSD = false
  @AppStorage(Settings.Key.osdDurationMs) private var osdDurationMs = Settings.defaultOSDDurationMs
  @AppStorage(Settings.Key.showOSDInMissionControl) private var showOSDInMissionControl = false

  @State private var launchAtLogin = false
  @State private var loginItemError: String?

  var body: some View {
    Form {
      Section("System") {
        Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
        Toggle("Override swipe gesture", isOn: $swipeOverride)
        Toggle(isOn: $overlayDetection) {
          Text("Enable Mission Control/Exposé detection")
          Text("Experimental—may be flaky")
        }
      }

      Section("On-Screen Display") {
        Toggle("Show when switching spaces", isOn: $showOSD)
        Picker("Duration", selection: $osdDurationMs) {
          ForEach(Self.durationPresets, id: \.self) { Text("\($0) ms").tag($0) }
        }
        .disabled(!showOSD)
        // Without detection the OSD can't tell Mission Control apart, so it always shows there
        Toggle("Show in Mission Control", isOn: Binding(
          get: { !overlayDetection || showOSDInMissionControl },
          set: { showOSDInMissionControl = $0 }
        ))
        .disabled(!showOSD || !overlayDetection)
      }
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .frame(width: 500)
    .fixedSize(horizontal: false, vertical: true)
    .onChange(of: swipeOverride) { _, enabled in iss_set_swipe_override(enabled) }
    .onChange(of: overlayDetection) { _, enabled in iss_set_overlay_detection_enabled(enabled) }
    // Login items can change in System Settings while this view stays loaded
    .onAppear(perform: refreshLaunchAtLogin)
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      refreshLaunchAtLogin()
    }
    .alert("Couldn't change launch at login", isPresented: Binding(isPresent: $loginItemError), presenting: loginItemError) { _ in
    } message: { error in
      Text(error)
    }
  }

  private func refreshLaunchAtLogin() {
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      loginItemError = error.localizedDescription
    }
    refreshLaunchAtLogin()
    if enabled && SMAppService.mainApp.status == .requiresApproval {
      SMAppService.openSystemSettingsLoginItems()
    }
  }
}

extension Binding where Value == Bool {
  /// True while `item` has a value; setting false clears it. For alerts driven by an optional.
  init<Item>(isPresent item: Binding<Item?>) {
    self.init(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
  }
}
