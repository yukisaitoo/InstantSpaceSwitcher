import AppKit
import ISS

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
  weak var delegate: MenuBarControllerDelegate?

  private var statusItem: NSStatusItem!
  private var switchItems: [HotkeyIdentifier: NSMenuItem] = [:]
  private var cachedSpaceInfo: ISSSpaceInfo?
  private var refreshWorkItem: DispatchWorkItem?

  private lazy var baseStatusImage: NSImage? = {
    let image = NSImage(
      systemSymbolName: "arrow.left.and.right.square", accessibilityDescription: Constants.appName)
    image?.isTemplate = true
    return image
  }()

  func setup() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.menu = createMenu()
    updateStatusItemAppearance()
  }

  private func createMenu() -> NSMenu {
    let menu = NSMenu()
    menu.delegate = self

    let leftItem = NSMenuItem(
      title: "Switch Left", action: #selector(switchLeft), target: self, symbolName: "arrow.left")
    let rightItem = NSMenuItem(
      title: "Switch Right", action: #selector(switchRight), target: self, symbolName: "arrow.right")
    switchItems = [.left: leftItem, .right: rightItem]
    menu.addItem(leftItem)
    menu.addItem(rightItem)
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: "Settings…", action: #selector(openPreferences), keyEquivalent: ",", target: self,
        symbolName: "gearshape"))
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "About", action: #selector(openAbout), target: self, symbolName: "info.circle"))
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    return menu
  }

  @objc private func switchLeft(_ sender: Any?) {
    delegate?.menuBarController(self, didRequestSwitch: ISSDirectionLeft)
  }

  @objc private func switchRight(_ sender: Any?) {
    delegate?.menuBarController(self, didRequestSwitch: ISSDirectionRight)
  }

  @objc private func openPreferences(_ sender: Any?) {
    delegate?.menuBarControllerDidRequestPreferences(self)
  }

  @objc private func openAbout(_ sender: Any?) {
    delegate?.menuBarControllerDidRequestAbout(self)
  }

  func updateWithSpaceInfo(_ info: ISSSpaceInfo?) {
    cachedSpaceInfo = info
    updateMenuState()
  }

  func scheduleRefresh(after delay: TimeInterval) {
    refreshWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.delegate?.menuBarControllerDidRequestRefresh(self)
    }
    refreshWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
  }

  private func updateMenuState() {
    if let info = cachedSpaceInfo {
      switchItems[.left]?.isEnabled = info.currentIndex > 0
      switchItems[.right]?.isEnabled = info.currentIndex + 1 < info.spaceCount
    } else {
      switchItems[.left]?.isEnabled = true
      switchItems[.right]?.isEnabled = true
    }

    updateStatusItemAppearance()
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    scheduleRefresh(after: 0.05)
  }

  func menuWillOpen(_ menu: NSMenu) {
    scheduleRefresh(after: 0.05)
  }

  private func updateStatusItemAppearance() {
    guard let button = statusItem.button else { return }

    button.font = nil
    button.title = ""
    button.imagePosition = .imageOnly
    if let info = cachedSpaceInfo, let icon = MenuBarIconRenderer.renderIcon(for: info) {
      button.image = icon
    } else {
      button.image = baseStatusImage
    }
  }

  func setIconVisible(_ visible: Bool) {
    statusItem.isVisible = visible
  }

  func applyHotkey(_ combination: HotkeyCombination, to identifier: HotkeyIdentifier) {
    guard let menuItem = switchItems[identifier] else { return }
    menuItem.keyEquivalent = combination.keyEquivalent
    menuItem.keyEquivalentModifierMask = combination.cocoaModifierFlags
  }
}

@MainActor
protocol MenuBarControllerDelegate: AnyObject {
  func menuBarController(_ controller: MenuBarController, didRequestSwitch direction: ISSDirection)
  func menuBarControllerDidRequestPreferences(_ controller: MenuBarController)
  func menuBarControllerDidRequestAbout(_ controller: MenuBarController)
  func menuBarControllerDidRequestRefresh(_ controller: MenuBarController)
}
