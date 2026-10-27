import Carbon
import Combine

final class HotkeyManager: ObservableObject {
  static let shared = HotkeyManager()

  enum Issue: Equatable {
    case claimedByAnotherApp
    case refused(OSStatus)

    var message: String {
      switch self {
      case .claimedByAnotherApp: return "Another app has claimed this shortcut"
      case .refused(let status): return "macOS refused this shortcut (error \(status))"
      }
    }
  }

  private struct Entry {
    let combination: HotkeyCombination
    let handler: () -> Void
  }

  private static let signature: OSType = 0x4953_5320 // "ISS "

  /// Shortcuts that are enabled but not working.
  @Published private(set) var issues: [HotkeyIdentifier: Issue] = [:]

  private var entries: [HotkeyIdentifier: Entry] = [:]
  private var refs: [HotkeyIdentifier: EventHotKeyRef] = [:]

  /// While paused nothing is registered, so the keys reach the shortcut recorder.
  var isPaused = false {
    didSet {
      guard isPaused != oldValue else { return }
      for identifier in entries.keys {
        isPaused ? unregisterCarbon(identifier) : registerCarbon(identifier)
      }
    }
  }

  private init() {
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
      var hotKeyID = EventHotKeyID()
      let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
      )
      guard status == noErr, hotKeyID.signature == HotkeyManager.signature else {
        return OSStatus(eventNotHandledErr)
      }
      HotkeyManager.shared.fire(id: hotKeyID.id)
      return noErr
    }, 1, &eventType, nil, nil)
  }

  func register(
    identifier: HotkeyIdentifier, combination: HotkeyCombination, handler: @escaping () -> Void
  ) {
    unregister(identifier: identifier)
    entries[identifier] = Entry(combination: combination, handler: handler)
    if !isPaused {
      registerCarbon(identifier)
    }
  }

  func unregister(identifier: HotkeyIdentifier) {
    unregisterCarbon(identifier)
    entries.removeValue(forKey: identifier)
    issues.removeValue(forKey: identifier)
  }

  private func registerCarbon(_ identifier: HotkeyIdentifier) {
    guard let combination = entries[identifier]?.combination else { return }
    var ref: EventHotKeyRef?
    let id = EventHotKeyID(signature: Self.signature, id: identifier.carbonID)
    let register = { (options: Int) in
      RegisterEventHotKey(
        combination.keyCode, combination.modifiers, id, GetApplicationEventTarget(), OptionBits(options), &ref
      )
    }
    // Exclusive keeps apps that registered the same keys normally (e.g. Rectangle) from also getting them.
    // macOS keeps its own keys like ⌃← exclusively registered even when they're turned off in System
    // Settings; a normal registration still works for those.
    var status = register(kEventHotKeyExclusive)
    if status == eventHotKeyExistsErr {
      status = register(0)
    }
    if status == noErr, let ref {
      refs[identifier] = ref
      issues.removeValue(forKey: identifier)
    } else {
      issues[identifier] = status == eventHotKeyExistsErr ? .claimedByAnotherApp : .refused(status)
    }
  }

  private func unregisterCarbon(_ identifier: HotkeyIdentifier) {
    if let ref = refs.removeValue(forKey: identifier) {
      UnregisterEventHotKey(ref)
    }
  }

  private func fire(id: UInt32) {
    entries.first { $0.key.carbonID == id }?.value.handler()
  }
}

private extension HotkeyIdentifier {
  var carbonID: UInt32 {
    switch self {
    case .left: return 1
    case .right: return 2
    }
  }
}
