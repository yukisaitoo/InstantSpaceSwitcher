import AppKit

extension NSMenuItem {
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
