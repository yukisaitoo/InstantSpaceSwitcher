import AppKit
import ISS

final class OSDWindow {
  static let shared = OSDWindow()

  private static let size: CGFloat = 140

  private let window: NSWindow
  private let label: NSTextField
  private var hideTimer: Timer?

  private init() {
    let frame = NSRect(x: 0, y: 0, width: Self.size, height: Self.size)
    window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.level = .statusBar
    // Not on all spaces: each number stays on the space it belongs to instead of
    // riding along onto the next one until that space's number is shown
    window.collectionBehavior = [.ignoresCycle]
    window.ignoresMouseEvents = true
    window.hidesOnDeactivate = false
    window.animationBehavior = .none

    let background = NSVisualEffectView(frame: frame)
    background.material = .hudWindow
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = 18
    background.layer?.masksToBounds = true

    label = NSTextField(labelWithString: "")
    label.font = NSFont.systemFont(ofSize: 48, weight: .medium)
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false

    background.addSubview(label)
    window.contentView = background

    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: background.centerYAnchor)
    ])
  }

  func show(message: String) {
    guard Settings.showOSD else { return }
    if iss_is_mission_control_active() && !Settings.showOSDInMissionControl {
      return
    }

    hideTimer?.invalidate()
    hideTimer = nil

    label.stringValue = message

    let mouseLocation = NSEvent.mouseLocation
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main {
      let screenFrame = screen.visibleFrame
      window.setFrameOrigin(NSPoint(x: screenFrame.midX - Self.size / 2, y: screenFrame.midY - Self.size / 2))
    }

    // Alpha applies in the WindowServer at once, but the label only redraws on the
    // next display pass, so draw it first or the first frame shows the old number
    window.contentView?.layoutSubtreeIfNeeded()
    window.display()
    CATransaction.flush()

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      window.animator().alphaValue = 1.0
    }
    if !window.isOnActiveSpace {
      // Still on the previous space; ordering in again puts it on this one
      window.orderOut(nil)
    }
    window.orderFrontRegardless()

    let duration = Double(Settings.osdDurationMs) / 1000.0
    hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
      self?.hide()
    }
  }

  // Smooth: the old number stays on its space and slides away with it. Instant
  // has no slide, and the old number flickers by on the way, so remove it first.
  func switchWillStart() {
    guard !Settings.smoothSwitching else { return }
    hideTimer?.invalidate()
    hideTimer = nil
    // Through the animator so it also cancels a fade in progress
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      window.animator().alphaValue = 0.0
    }
    window.orderOut(nil)
  }

  private func hide() {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      window.animator().alphaValue = 0.0
    }
  }
}
