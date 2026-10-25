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
  private lazy var osdDurationPopup = popup(
    titles: durationPresets.map { "\($0)ms" }, action: #selector(osdDurationChanged))
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

  private func popup(titles: [String], action: Selector) -> NSPopUpButton {
    let popup = NSPopUpButton()
    popup.addItems(withTitles: titles)
    popup.target = self
    popup.action = action
    return popup
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
    launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    swipeOverrideCheckbox.state = Settings.swipeOverride ? .on : .off
    overlayDetectionCheckbox.state = Settings.overlayDetectionEnabled ? .on : .off

    showOSDCheckbox.state = Settings.showOSD ? .on : .off
    osdDurationPopup.selectItem(at: durationPresets.firstIndex(of: Settings.osdDurationMs) ?? 1)
    showOSDInMissionControlCheckbox.state = Settings.showOSDInMissionControl ? .on : .off
    updateDependentControls()
  }

  private func updateDependentControls() {
    let showOSD = showOSDCheckbox.state == .on
    osdDurationPopup.isEnabled = showOSD
    showOSDInMissionControlCheckbox.isEnabled = showOSD && overlayDetectionCheckbox.state == .on
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
    guard durationPresets.indices.contains(sender.indexOfSelectedItem) else { return }
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
      NSSound.beep()
      sender.state = shouldEnable ? .off : .on
      Alerts.showWarning(
        "Failed to \(shouldEnable ? "enable" : "disable") launch at login", info: error.localizedDescription)
    }
  }
}
