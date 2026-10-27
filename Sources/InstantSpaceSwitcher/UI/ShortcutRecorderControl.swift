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
      guard isRecording != oldValue else { return }
      needsDisplay = true
      HotkeyManager.shared.isPaused = isRecording
      if isRecording {
        Self.activeRecorder = self
        monitor = NSEvent.addLocalMonitorForEvents(
          matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
          guard let self else { return event }
          if event.type == .keyDown {
            handleKeyEvent(event)
            return nil
          }
          isRecording = false
          // A click on this recorder only cancels; anywhere else it also does its usual job
          let clickedSelf = event.window == window && bounds.contains(convert(event.locationInWindow, from: nil))
          return clickedSelf ? nil : event
        }
      } else {
        if let monitor {
          NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if Self.activeRecorder === self {
          Self.activeRecorder = nil
        }
      }
    }
  }

  var currentShortcut: HotkeyCombination? {
    didSet {
      needsDisplay = true
    }
  }

  var onRecordingComplete: ((HotkeyCombination) -> Void)?

  private var monitor: Any?

  private func handleKeyEvent(_ event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) {
      isRecording = false
      return
    }

    guard let combination = HotkeyCombination.from(event: event), combination.isValid else {
      NSSound.beep()
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
    isRecording = true
  }
}
