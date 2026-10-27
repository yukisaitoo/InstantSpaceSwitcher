import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
  convenience init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 550, height: 350),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )

    window.title = "\(Constants.appName) Settings"
    window.contentViewController = PreferencesTabViewController()
    window.isReleasedWhenClosed = false
    window.center()

    self.init(window: window)
    window.delegate = self
  }

  func present() {
    if !AXIsProcessTrusted() {
      Alerts.showAccessibilityPermissionRequired(to: "switch spaces")
    }

    guard let window else { return }

    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    // Otherwise the window focuses its first control, often a shortcut recorder
    window.makeFirstResponder(nil)
    // Activation is only a request macOS may decline; this shows the window regardless
    window.orderFrontRegardless()
  }
}

extension PreferencesWindowController: NSWindowDelegate {
  func windowDidResignKey(_ notification: Notification) {
    ShortcutRecorderControl.cancelActiveRecording()
  }
}

private final class PreferencesTabViewController: NSTabViewController {
  override func viewDidLoad() {
    super.viewDidLoad()

    tabStyle = .toolbar
    addTab(GeneralSettingsView(), label: "General", symbolName: "gearshape")
    addTab(KeyboardSettingsView(), label: "Keyboard", symbolName: "keyboard")
  }

  private func addTab(_ view: some View, label: String, symbolName: String) {
    let hostingController = NSHostingController(rootView: view)
    // Lets the tab controller resize the window to each tab's content
    hostingController.sizingOptions = .preferredContentSize
    let item = NSTabViewItem(viewController: hostingController)
    item.label = label
    item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
    addTabViewItem(item)
  }
}
