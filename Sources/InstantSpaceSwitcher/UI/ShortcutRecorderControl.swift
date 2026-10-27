import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
  let title: String
  let combination: HotkeyCombination
  let isEnabled: Bool
  let onRecord: (HotkeyCombination) -> Void

  final class Coordinator {
    var onRecord: (HotkeyCombination) -> Void

    init(onRecord: @escaping (HotkeyCombination) -> Void) {
      self.onRecord = onRecord
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onRecord: onRecord)
  }

  func makeNSView(context: Context) -> ShortcutRecorderControl {
    let recorder = ShortcutRecorderControl()
    // Goes through the coordinator so the control never calls a closure from an outdated view
    let coordinator = context.coordinator
    recorder.onRecordingComplete = { coordinator.onRecord($0) }
    return recorder
  }

  func updateNSView(_ recorder: ShortcutRecorderControl, context: Context) {
    context.coordinator.onRecord = onRecord
    recorder.title = title
    if recorder.currentShortcut != combination {
      recorder.currentShortcut = combination
    }
    if recorder.isEnabled != isEnabled {
      recorder.isEnabled = isEnabled
    }
  }
}

final class ShortcutRecorderControl: NSView {
  private static weak var activeRecorder: ShortcutRecorderControl?

  static func cancelActiveRecording() {
    activeRecorder?.isRecording = false
  }

  var title = "" {
    didSet { setAccessibilityLabel(title) }
  }

  var isEnabled = true {
    didSet {
      needsDisplay = true
      alphaValue = isEnabled ? 1.0 : 0.5
      setAccessibilityEnabled(isEnabled)
    }
  }

  var isRecording = false {
    didSet {
      guard isRecording != oldValue else { return }
      needsDisplay = true
      updateAccessibilityValue()
      isRecording ? startRecording() : stopRecording()
    }
  }

  var currentShortcut: HotkeyCombination? {
    didSet {
      needsDisplay = true
      updateAccessibilityValue()
    }
  }

  var onRecordingComplete: ((HotkeyCombination) -> Void)?

  private var monitor: Any?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    updateAccessibilityValue()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 22) }

  // Like a native button: keyboard focus only with Keyboard navigation turned on in System Settings
  override var acceptsFirstResponder: Bool { isEnabled && NSApp.isFullKeyboardAccessEnabled }
  override var canBecomeKeyView: Bool { acceptsFirstResponder }
  override var focusRingMaskBounds: NSRect { bounds }

  override func drawFocusRingMask() {
    roundedPath.fill()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // A recorder removed mid-recording would otherwise leave every hotkey paused
    if window == nil {
      isRecording = false
    }
  }

  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    isRecording = true
  }

  override func keyDown(with event: NSEvent) {
    let startsRecording = event.keyCode == UInt16(kVK_Space) || event.keyCode == UInt16(kVK_Return)
    if !isRecording, startsRecording, event.modifierFlags.carbonMask == 0 {
      isRecording = true
    } else {
      super.keyDown(with: event)
    }
  }

  override func accessibilityPerformPress() -> Bool {
    guard isEnabled else { return false }
    isRecording = true
    return true
  }

  private func startRecording() {
    Self.activeRecorder?.isRecording = false
    Self.activeRecorder = self
    HotkeyManager.shared.isPaused = true
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
  }

  private func stopRecording() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    guard Self.activeRecorder === self else { return }
    Self.activeRecorder = nil
    HotkeyManager.shared.isPaused = false
  }

  private func handleKeyEvent(_ event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) {
      isRecording = false
      return
    }

    let combination = HotkeyCombination(event: event)
    guard combination.isValid else {
      NSSound.beep()
      return
    }

    isRecording = false
    onRecordingComplete?(combination)
  }

  private func updateAccessibilityValue() {
    setAccessibilityValue(isRecording ? "Recording" : currentShortcut?.displayString ?? "None")
  }

  private var roundedPath: NSBezierPath {
    NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    if isRecording {
      NSColor.selectedControlColor.withAlphaComponent(0.3).setFill()
    } else {
      NSColor.controlBackgroundColor.setFill()
    }

    let path = roundedPath
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
}
