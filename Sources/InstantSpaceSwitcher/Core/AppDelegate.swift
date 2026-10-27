import AppKit
import Combine
import ISS

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let hotkeyStore = HotkeyStore.shared
  private lazy var preferencesWindowController = PreferencesWindowController()
  private var cancellables = Set<AnyCancellable>()

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    preferencesWindowController.present()
    return false
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    ensureAccessibilityPermission()

    if !iss_init() {
      scheduleIssInitRetry()
    }

    if Settings.swipeOverride {
      iss_set_swipe_override(true)
    }
    if Settings.overlayDetectionEnabled {
      iss_set_overlay_detection_enabled(true)
    }

    iss_set_switch_callback { newSpaceIndex in
      DispatchQueue.main.async {
        OSDWindow.shared.show(message: "\(Int(newSpaceIndex) + 1)")
      }
    }

    setupMainMenu()
    bindHotkeys()
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { _ in
      iss_space_did_change()
    }
  }

  private func scheduleIssInitRetry() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      if !iss_init() {
        self?.scheduleIssInitRetry()
      }
    }
  }

  private func ensureAccessibilityPermission() {
    guard !AXIsProcessTrusted() else { return }

    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [promptKey: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  private func setupMainMenu() {
    let appMenu = NSMenu(title: Constants.appName)
    appMenu.addItem(NSMenuItem(title: "About", action: #selector(openAbout), target: self, symbolName: "info.circle"))
    appMenu.addItem(.separator())
    appMenu.addItem(
      NSMenuItem(
        title: "Settings…", action: #selector(openPreferences), keyEquivalent: ",", target: self,
        symbolName: "gearshape"))
    appMenu.addItem(.separator())

    let servicesItem = NSMenuItem(title: "Services", action: nil)
    servicesItem.submenu = NSMenu()
    NSApp.servicesMenu = servicesItem.submenu
    appMenu.addItem(servicesItem)
    appMenu.addItem(.separator())

    appMenu.addItem(
      NSMenuItem(
        title: "Hide \(Constants.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h",
        target: NSApp))
    let hideOthersItem = NSMenuItem(
      title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h",
      target: NSApp)
    hideOthersItem.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(hideOthersItem)
    appMenu.addItem(
      NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), target: NSApp))
    appMenu.addItem(.separator())
    appMenu.addItem(
      NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q", target: NSApp))

    let fileMenu = NSMenu(title: "File")
    fileMenu.addItem(
      NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

    let mainMenu = NSMenu()
    for submenu in [appMenu, fileMenu] {
      let item = NSMenuItem()
      item.submenu = submenu
      mainMenu.addItem(item)
    }
    NSApp.mainMenu = mainMenu
  }

  @objc private func openPreferences(_ sender: Any?) {
    preferencesWindowController.present()
  }

  @objc private func openAbout(_ sender: Any?) {
    NSApp.activate()

    var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
    if let gitHash = Bundle.main.object(forInfoDictionaryKey: "GitCommitHash") as? String {
      options[.version] = gitHash
    }
    NSApp.orderFrontStandardAboutPanel(options: options)
  }

  private func bindHotkeys() {
    hotkeyStore.$hotkeys.combineLatest(hotkeyStore.$enabledStates)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.reregisterAllHotkeys() }
      .store(in: &cancellables)
  }

  private func reregisterAllHotkeys() {
    for identifier in HotkeyIdentifier.allCases {
      registerHotkey(identifier)
    }
  }

  private func registerHotkey(_ identifier: HotkeyIdentifier) {
    let combination = hotkeyStore.combination(for: identifier)

    // Shortcuts saved by older versions may no longer be valid
    guard hotkeyStore.isEnabled(identifier), combination.isValid else {
      HotkeyManager.shared.unregister(identifier: identifier)
      return
    }

    HotkeyManager.shared.register(identifier: identifier, combination: combination) {
      // Skipped switches stay silent: people tap around to find where they are
      _ = iss_switch(identifier == .left ? ISSDirectionLeft : ISSDirectionRight)
    }
  }
}

private extension NSMenuItem {
  convenience init(
    title: String, action: Selector?, keyEquivalent: String = "", target: AnyObject? = nil,
    symbolName: String? = nil
  ) {
    self.init(title: title, action: action, keyEquivalent: keyEquivalent)
    self.target = target
    if let symbolName {
      image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }
  }
}
