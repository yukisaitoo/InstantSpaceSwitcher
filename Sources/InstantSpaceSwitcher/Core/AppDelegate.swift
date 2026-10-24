import AppKit
import ApplicationServices
import Combine
import ISS

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let menuBarController = MenuBarController()
  private let hotkeyStore = HotkeyStore.shared
  private lazy var preferencesWindowController = PreferencesWindowController()
  private var currentSpaceIndex: UInt32?
  private var cancellables = Set<AnyCancellable>()
  private var spaceChangeObserver: Any?
  private var appActivationObserver: Any?

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleReopen),
      forEventClass: kCoreEventClass,
      andEventID: kAEReopenApplication
    )
  }

  @objc private func handleReopen(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
    preferencesWindowController.present()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    ensureAccessibilityPermission()

    if !iss_init() {
      print("Failed to initialize ISS event tap")
      retryIssInit()
    }

    if UserDefaults.standard.bool(forKey: "swipeOverride") {
      iss_set_swipe_override(true)
    }

    let gestureSpeed = UserDefaults.standard.double(forKey: "gestureSpeed")
    if gestureSpeed > 0 {
      iss_set_gesture_speed(gestureSpeed)
    }

    // No UI; tune with: defaults write com.interversehq.InstantSpaceSwitcher edgeGestureSpeed -float 400
    let edgeGestureSpeed = UserDefaults.standard.double(forKey: "edgeGestureSpeed")
    if edgeGestureSpeed > 0 {
      iss_set_edge_gesture_speed(edgeGestureSpeed)
    }

    if UserDefaults.standard.object(forKey: "overlayDetectionEnabled") as? Bool ?? true {
      iss_set_overlay_detection_enabled(true)
    }

    iss_set_switch_callback { newSpaceIndex in
      DispatchQueue.main.async {
        OSDWindow.shared.show(message: "\(Int(newSpaceIndex) + 1)")
      }
    }

    setupMainMenu()
    menuBarController.delegate = self
    menuBarController.setup()

    if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
      menuBarController.setIconVisible(false)
    }

    bindHotkeys()
    observeSpaceChanges()
    observeAppActivation()
    refreshSpaceInfo()
  }

  func applicationWillTerminate(_ notification: Notification) {
    iss_destroy()
    stopObservingSpaceChanges()
    stopObservingAppActivation()
  }

  private func retryIssInit() {
    guard !iss_init() else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.retryIssInit()
    }
  }

  private func ensureAccessibilityPermission() {
    guard !AXIsProcessTrusted() else { return }

    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [promptKey: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  private func setupMainMenu() {
    let mainMenu = NSMenu()

    // App menu
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)

    let appMenu = NSMenu(title: Constants.appName)
    appMenuItem.submenu = appMenu

    let aboutItem = NSMenuItem(
      title: "About", action: #selector(openAbout(_:)), keyEquivalent: "")
    aboutItem.target = self
    aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
    appMenu.addItem(aboutItem)

    appMenu.addItem(NSMenuItem.separator())

    let preferencesItem = NSMenuItem(
      title: "Settings…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
    preferencesItem.target = self
    preferencesItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
    appMenu.addItem(preferencesItem)

    appMenu.addItem(NSMenuItem.separator())

    let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
    let servicesMenu = NSMenu()
    servicesItem.submenu = servicesMenu
    NSApp.servicesMenu = servicesMenu
    appMenu.addItem(servicesItem)

    appMenu.addItem(NSMenuItem.separator())

    let hideItem = NSMenuItem(
      title: "Hide \(Constants.appName)", action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h")
    hideItem.target = NSApp
    appMenu.addItem(hideItem)

    let hideOthersItem = NSMenuItem(
      title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h")
    hideOthersItem.keyEquivalentModifierMask = [.command, .option]
    hideOthersItem.target = NSApp
    appMenu.addItem(hideOthersItem)

    let showAllItem = NSMenuItem(
      title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: "")
    showAllItem.target = NSApp
    appMenu.addItem(showAllItem)

    appMenu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(
      title: "Quit", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    quitItem.target = NSApp
    appMenu.addItem(quitItem)

    // File menu
    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)

    let fileMenu = NSMenu(title: "File")
    fileMenuItem.submenu = fileMenu

    let closeItem = NSMenuItem(
      title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    fileMenu.addItem(closeItem)

    NSApp.mainMenu = mainMenu
  }

  @objc private func openPreferences(_ sender: Any?) {
    preferencesWindowController.present()
  }

  @objc private func openAbout(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(sender)
    // Ensure window comes to front if already open
    NSApp.windows.first(where: { $0.title.contains("About") })?.makeKeyAndOrderFront(nil)
  }

  private func bindHotkeys() {
    hotkeyStore.$leftHotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .left, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$rightHotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .right, combination: $0)
    }.store(in: &cancellables)

    hotkeyStore.$enabledStates.receive(on: RunLoop.main).sink { [weak self] _ in
      guard let self = self else { return }
      for identifier in HotkeyIdentifier.allCases {
        self.registerHotkey(
          for: identifier, combination: self.hotkeyStore.combination(for: identifier))
      }
    }.store(in: &cancellables)
  }

  func setMenuBarIconVisible(_ visible: Bool) {
    menuBarController.setIconVisible(visible)
  }

  func reregisterAllHotkeys() {
    for identifier in HotkeyIdentifier.allCases {
      let combination = hotkeyStore.combination(for: identifier)
      menuBarController.applyHotkey(combination, to: identifier)
      registerHotkey(for: identifier, combination: combination)
    }
  }

  private func registerHotkey(for identifier: HotkeyIdentifier, combination: HotkeyCombination) {
    menuBarController.applyHotkey(combination, to: identifier)

    // combination.isValid guards against modifier-less hotkeys persisted by
    // older versions, which would swallow a bare key system-wide
    guard hotkeyStore.isEnabled(identifier), combination.isValid else {
      HotKeyManager.shared.unregister(identifier: identifier)
      return
    }

    HotKeyManager.shared.register(identifier: identifier, combination: combination) { [weak self] in
      guard let self else { return }
      switch identifier {
      case .left:
        self.performSpaceSwitch(ISSDirectionLeft)
      case .right:
        self.performSpaceSwitch(ISSDirectionRight)
      }
    }
  }

  private func performSpaceSwitch(_ direction: ISSDirection) {
    if !iss_switch(direction) {
      NSSound.beep()
      return
    }
    refreshSpaceInfo()
  }

  private func refreshSpaceInfo() {
    var info = ISSSpaceInfo()
    if iss_get_menubar_space_info(&info) {
      currentSpaceIndex = info.currentIndex

      menuBarController.updateWithSpaceInfo(info)
    } else {
      menuBarController.updateWithSpaceInfo(nil)
    }
  }

  private func observeSpaceChanges() {
    stopObservingSpaceChanges()
    spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.refreshSpaceInfo()
        iss_reset_predictions()
        self.menuBarController.scheduleRefresh(after: 0.2)
      }
    }
  }

  private func stopObservingSpaceChanges() {
    if let observer = spaceChangeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      spaceChangeObserver = nil
    }
  }

  private func observeAppActivation() {
    stopObservingAppActivation()
    appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.menuBarController.scheduleRefresh(after: 0.1)
      }
    }
  }

  private func stopObservingAppActivation() {
    if let observer = appActivationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      appActivationObserver = nil
    }
  }

}

extension AppDelegate: MenuBarControllerDelegate {
  func menuBarControllerDidRequestSwitchLeft(_ controller: MenuBarController) {
    performSpaceSwitch(ISSDirectionLeft)
  }

  func menuBarControllerDidRequestSwitchRight(_ controller: MenuBarController) {
    performSpaceSwitch(ISSDirectionRight)
  }

  func menuBarControllerDidRequestPreferences(_ controller: MenuBarController) {
    preferencesWindowController.present()
  }

  func menuBarControllerDidRequestRefresh(_ controller: MenuBarController) {
    refreshSpaceInfo()
  }
}
