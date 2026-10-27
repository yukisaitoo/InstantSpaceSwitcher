import AppKit
import ISS
import ServiceManagement

final class GeneralSettingsViewController: NSViewController {
  private let durationPresets = [100, 200, 300, 500, 750, 1000]

  private let formView = FormView()

  private lazy var launchAtLoginCheckbox = NSButton(
    checkboxWithTitle: "Launch at login", target: self, action: #selector(launchAtLoginChanged))
  private lazy var swipeOverrideCheckbox = NSButton(
    checkboxWithTitle: "Override swipe gesture", target: self, action: #selector(swipeOverrideChanged))
  private lazy var overlayDetectionCheckbox: NSButton = {
    let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(overlayDetectionChanged))
    let title = NSMutableAttributedString(string: "Enable Mission Control/Exposé detection\n")
    title.append(
      NSAttributedString(
        string: "Experimental—may be flaky",
        attributes: [
          .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
          .foregroundColor: NSColor.secondaryLabelColor
        ]))
    checkbox.attributedTitle = title
    return checkbox
  }()
  private lazy var showOSDCheckbox = NSButton(
    checkboxWithTitle: "Show for", target: self, action: #selector(showOSDChanged))
  private lazy var osdDurationPopup: NSPopUpButton = {
    let popup = NSPopUpButton()
    popup.addItems(withTitles: durationPresets.map { "\($0)ms" })
    popup.target = self
    popup.action = #selector(osdDurationChanged)
    return popup
  }()
  private lazy var showOSDInMissionControlCheckbox = NSButton(
    checkboxWithTitle: "Show in Mission Control", target: self, action: #selector(showOSDInMissionControlChanged))

  override func loadView() {
    view = formView
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    setupUI()
    loadSettings()
  }

  private func setupUI() {
    formView.addRow(title: "System:", control: launchAtLoginCheckbox)
    formView.addRow(label: nil, control: swipeOverrideCheckbox)
    formView.addRow(label: nil, control: overlayDetectionCheckbox)
    formView.addSectionSpacing()

    let osdRow = NSStackView()
    osdRow.orientation = .horizontal
    osdRow.spacing = 8
    osdRow.addArrangedSubview(showOSDCheckbox)
    osdRow.addArrangedSubview(osdDurationPopup)
    osdRow.addArrangedSubview(NSTextField(labelWithString: "when switching spaces"))
    formView.addRow(title: "On-Screen Display:", control: osdRow)
    formView.addRow(label: nil, control: showOSDInMissionControlCheckbox)
  }

  private func loadSettings() {
    refreshLaunchAtLogin()
    swipeOverrideCheckbox.state = Settings.swipeOverride ? .on : .off
    overlayDetectionCheckbox.state = Settings.overlayDetectionEnabled ? .on : .off

    showOSDCheckbox.state = Settings.showOSD ? .on : .off
    let duration = durationPresets.contains(Settings.osdDurationMs) ? Settings.osdDurationMs : Settings.defaultOSDDurationMs
    osdDurationPopup.selectItem(at: durationPresets.firstIndex(of: duration) ?? 0)
    updateDependentControls()
  }

  // Login items can change in System Settings while this view stays loaded
  override func viewWillAppear() {
    super.viewWillAppear()
    refreshLaunchAtLogin()
  }

  private func refreshLaunchAtLogin() {
    launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
  }

  private func updateDependentControls() {
    let showOSD = showOSDCheckbox.state == .on
    let detectsOverlay = overlayDetectionCheckbox.state == .on
    osdDurationPopup.isEnabled = showOSD
    showOSDInMissionControlCheckbox.isEnabled = showOSD && detectsOverlay
    // Without detection the OSD can't tell Mission Control apart, so it always shows there
    showOSDInMissionControlCheckbox.state = !detectsOverlay || Settings.showOSDInMissionControl ? .on : .off
  }

  @objc private func showOSDChanged(_ sender: NSButton) {
    Settings.showOSD = sender.state == .on
    updateDependentControls()
  }

  @objc private func overlayDetectionChanged(_ sender: NSButton) {
    let isEnabled = sender.state == .on
    Settings.overlayDetectionEnabled = isEnabled
    iss_set_overlay_detection_enabled(isEnabled)
    updateDependentControls()
  }

  @objc private func showOSDInMissionControlChanged(_ sender: NSButton) {
    Settings.showOSDInMissionControl = sender.state == .on
  }

  @objc private func osdDurationChanged(_ sender: NSPopUpButton) {
    Settings.osdDurationMs = durationPresets[sender.indexOfSelectedItem]
  }

  @objc private func swipeOverrideChanged(_ sender: NSButton) {
    let isEnabled = sender.state == .on
    Settings.swipeOverride = isEnabled
    iss_set_swipe_override(isEnabled)
  }

  @objc private func launchAtLoginChanged(_ sender: NSButton) {
    let shouldEnable = sender.state == .on

    do {
      if shouldEnable {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      Alerts.showWarning(
        "Failed to \(shouldEnable ? "enable" : "disable") launch at login", info: error.localizedDescription)
    }
    refreshLaunchAtLogin()
    if shouldEnable && SMAppService.mainApp.status == .requiresApproval {
      SMAppService.openSystemSettingsLoginItems()
    }
  }
}
