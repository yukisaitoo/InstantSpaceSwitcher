import AppKit

enum Alerts {
  static func showAccessibilityPermissionRequired(to purpose: String) {
    NSApp.activate()

    let alert = NSAlert()
    alert.messageText = "Accessibility Permission Required"
    alert.informativeText = """
      \(Constants.appName) needs Accessibility permission to \(purpose).

      Please enable it in System Settings > Privacy & Security > Accessibility.

      If \(Constants.appName) already appears in that list but isn't working \
      (common after updating the app), remove it with the − button, add it again, \
      then relaunch \(Constants.appName).
      """
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn,
      let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  static func showWarning(_ message: String, info: String) {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = info
    alert.alertStyle = .warning
    alert.runModal()
  }
}
