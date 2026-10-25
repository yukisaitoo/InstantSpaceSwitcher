import AppKit
import Carbon

final class ShortcutRecorderControl: NSView {
  private static weak var activeRecorder: ShortcutRecorderControl?

  static func cancelActiveRecording() {
    activeRecorder?.isRecording = false
  }

  var isEnabled = true {
    didSet {
      needsDisplay = true
      alphaValue = isEnabled ? 1.0 : 0.5
    }
  }

  var isRecording = false {
    didSet {
      needsDisplay = true
      if isRecording {
        keyPressed = false
        HotkeyManager.shared.unregisterAll()
        startEventTapRecording()
        Self.activeRecorder = self
      } else {
        GlobalEventTapRecorder.shared.stopRecording()
        if Self.activeRecorder === self {
          Self.activeRecorder = nil
        }
        (NSApp.delegate as? AppDelegate)?.reregisterAllHotkeys()
      }
    }
  }

  private var keyPressed = false

  var currentShortcut: HotkeyCombination? {
    didSet {
      needsDisplay = true
    }
  }

  var onRecordingComplete: ((HotkeyCombination) -> Void)?

  override var acceptsFirstResponder: Bool { true }
  override var canBecomeKeyView: Bool { true }

  private func startEventTapRecording() {
    let started = GlobalEventTapRecorder.shared.startRecording(
      onKeyPress: { [weak self] event in
        self?.handleKeyEvent(event)
      },
      onMouseClick: { [weak self] in
        self?.isRecording = false
      }
    )
    if !started {
      NSSound.beep()
      // Deferred: we're inside isRecording's didSet, which hasn't set activeRecorder yet
      DispatchQueue.main.async { [weak self] in
        self?.isRecording = false
      }
    }
  }

  private func handleKeyEvent(_ event: NSEvent) {
    guard !keyPressed else {
      NSSound.beep()
      return
    }

    keyPressed = true

    if event.keyCode == UInt16(kVK_Escape) {
      isRecording = false
      return
    }

    guard let combination = HotkeyCombination.from(event: event), combination.isValid else {
      NSSound.beep()
      keyPressed = false
      return
    }

    isRecording = false
    onRecordingComplete?(combination)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    if isRecording {
      NSColor.selectedControlColor.withAlphaComponent(0.3).setFill()
    } else {
      NSColor.controlBackgroundColor.setFill()
    }

    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
    path.fill()

    NSColor.separatorColor.setStroke()
    path.lineWidth = 1
    path.stroke()

    let text = isRecording ? "Press keys..." : (currentShortcut?.displayString ?? "Click to record")
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13),
      .foregroundColor: NSColor.labelColor
    ]

    let textSize = text.size(withAttributes: attributes)
    let textRect = NSRect(
      x: (bounds.width - textSize.width) / 2,
      y: (bounds.height - textSize.height) / 2,
      width: textSize.width,
      height: textSize.height
    )

    text.draw(in: textRect, withAttributes: attributes)
  }

  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }

    if !AXIsProcessTrusted() {
      Alerts.showAccessibilityPermissionRequired(to: "record keyboard shortcuts")
      return
    }

    if let activeRecorder = Self.activeRecorder, activeRecorder !== self {
      activeRecorder.isRecording = false
    }

    if !isRecording {
      isRecording = true
    }
  }
}
