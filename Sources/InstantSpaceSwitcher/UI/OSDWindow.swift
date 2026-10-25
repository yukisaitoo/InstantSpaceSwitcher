import AppKit
import ISS

final class OSDWindow {
  static let shared = OSDWindow()

  private static let size: CGFloat = 140

  private var window: NSWindow?
  private var label: NSTextField?
  private var hideTimer: Timer?

  private init() {}

  func show(message: String) {
    guard Settings.showOSD else { return }
    // Mission Control OSD suppression requires overlay detection enabled;
    // iss_is_mission_control_active() returns false when it's off
    if iss_is_mission_control_active() && !Settings.showOSDInMissionControl {
      return
    }

    hideTimer?.invalidate()
    hideTimer = nil

    if window == nil {
      createWindow()
    }
    guard let window, let label else { return }

    label.stringValue = message

    let mouseLocation = NSEvent.mouseLocation
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main {
      let screenFrame = screen.visibleFrame
      window.setFrameOrigin(NSPoint(x: screenFrame.midX - Self.size / 2, y: screenFrame.midY - Self.size / 2))
    }

    window.alphaValue = 1.0
    window.orderFrontRegardless()

    let duration = Double(Settings.osdDurationMs) / 1000.0
    hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
      self?.hide()
    }
  }

  private func createWindow() {
    let frame = NSRect(x: 0, y: 0, width: Self.size, height: Self.size)
    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.level = .statusBar
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]
    window.ignoresMouseEvents = true
    window.hidesOnDeactivate = false

    let visualEffect = NSVisualEffectView(frame: frame)
    visualEffect.material = .hudWindow
    visualEffect.state = .active
    visualEffect.wantsLayer = true
    visualEffect.layer?.cornerRadius = 18
    visualEffect.layer?.masksToBounds = true

    let label = NSTextField(labelWithString: "")
    label.font = NSFont.systemFont(ofSize: 48, weight: .medium)
    label.textColor = .labelColor
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false

    visualEffect.addSubview(label)
    window.contentView = visualEffect

    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor)
    ])

    self.window = window
    self.label = label
  }

  private func hide() {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      window?.animator().alphaValue = 0.0
    }
  }
}
