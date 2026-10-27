import AppKit

@main
enum InstantSpaceSwitcherApp {
  static func main() {
    let app = NSApplication.shared
    // NSApplication.delegate is weak; this local keeps the delegate alive while run() blocks
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }
}
