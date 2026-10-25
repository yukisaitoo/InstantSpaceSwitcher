import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController {
  convenience init() {
    let panel = PreferencesPanel(
      contentRect: NSRect(x: 0, y: 0, width: 550, height: 350),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )

    panel.title = "\(Constants.appName) Settings"
    panel.contentViewController = PreferencesTabViewController()
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.center()

    self.init(window: panel)
    panel.delegate = self
  }

  func present() {
    if !AXIsProcessTrusted() {
      Alerts.showAccessibilityPermissionRequired(to: "record keyboard shortcuts and switch spaces")
    }

    guard let window else { return }

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }
}

extension PreferencesWindowController: NSWindowDelegate {
  func windowDidResignKey(_ notification: Notification) {
    ShortcutRecorderControl.cancelActiveRecording()
  }
}

private final class PreferencesPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

private final class PreferencesTabViewController: NSTabViewController {
  override func viewDidLoad() {
    super.viewDidLoad()

    tabStyle = .toolbar
    addTab(GeneralSettingsViewController(), label: "General", symbolName: "gearshape")
    addTab(KeyboardShortcutsViewController(), label: "Keyboard", symbolName: "keyboard")
  }

  private func addTab(_ viewController: NSViewController, label: String, symbolName: String) {
    let item = NSTabViewItem(viewController: viewController)
    item.label = label
    item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
    addTabViewItem(item)
  }
}
