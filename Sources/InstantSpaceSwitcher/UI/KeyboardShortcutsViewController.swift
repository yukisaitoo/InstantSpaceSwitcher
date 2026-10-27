import AppKit
import Combine

private class RecordingView: NSView {
  override var acceptsFirstResponder: Bool { true }
  override func becomeFirstResponder() -> Bool { true }
}

final class KeyboardShortcutsViewController: NSViewController {
  private enum Column {
    static let enabled = NSUserInterfaceItemIdentifier("enabled")
    static let name = NSUserInterfaceItemIdentifier("name")
    static let shortcut = NSUserInterfaceItemIdentifier("shortcut")
  }

  private struct ShortcutRow {
    let identifier: HotkeyIdentifier
    var combination: HotkeyCombination
    var isEnabled: Bool
  }

  private let store = HotkeyStore.shared
  private var cancellables = Set<AnyCancellable>()
  private var shortcuts: [ShortcutRow] = []

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  override func loadView() {
    view = RecordingView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    setupTableView()
    loadShortcuts()
    bindStore()
  }

  private func setupTableView() {
    addColumn(Column.enabled, title: "Enabled", width: 80)
    addColumn(Column.name, title: "Action", width: 210)
    addColumn(Column.shortcut, title: "Shortcut", width: 210)

    tableView.delegate = self
    tableView.dataSource = self
    tableView.rowHeight = 28
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .bezelBorder
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    let resetAllButton = NSButton(
      title: "Reset All to Defaults", target: self, action: #selector(resetAllShortcuts))
    resetAllButton.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(scrollView)
    view.addSubview(resetAllButton)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      scrollView.bottomAnchor.constraint(equalTo: resetAllButton.topAnchor, constant: -12),

      resetAllButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      resetAllButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
    ])
  }

  private func addColumn(_ identifier: NSUserInterfaceItemIdentifier, title: String, width: CGFloat) {
    let column = NSTableColumn(identifier: identifier)
    column.title = title
    column.width = width
    tableView.addTableColumn(column)
  }

  private func loadShortcuts() {
    shortcuts = HotkeyIdentifier.allCases.map {
      ShortcutRow(identifier: $0, combination: store.combination(for: $0), isEnabled: store.isEnabled($0))
    }
    tableView.reloadData()
  }

  private func bindStore() {
    store.$hotkeys.combineLatest(store.$enabledStates)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
  }
}

extension KeyboardShortcutsViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    shortcuts.count
  }
}

extension KeyboardShortcutsViewController: NSTableViewDelegate {
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let column = tableColumn?.identifier else { return nil }
    let shortcut = shortcuts[row]

    switch column {
    case Column.enabled: return makeEnabledCell(for: shortcut, row: row)
    case Column.name: return makeNameCell(for: shortcut)
    case Column.shortcut: return makeShortcutCell(for: shortcut, row: row)
    default: return nil
    }
  }

  private func makeEnabledCell(for shortcut: ShortcutRow, row: Int) -> NSView {
    let cellView = NSTableCellView()
    let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
    checkbox.state = shortcut.isEnabled ? .on : .off
    checkbox.tag = row
    checkbox.translatesAutoresizingMaskIntoConstraints = false
    cellView.addSubview(checkbox)

    NSLayoutConstraint.activate([
      checkbox.centerXAnchor.constraint(equalTo: cellView.centerXAnchor),
      checkbox.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
    ])
    return cellView
  }

  private func makeNameCell(for shortcut: ShortcutRow) -> NSView {
    let cellView = NSTableCellView()
    let textField = NSTextField(labelWithString: shortcut.identifier.displayName)
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.textColor = shortcut.isEnabled ? .labelColor : .disabledControlTextColor
    cellView.addSubview(textField)
    cellView.textField = textField

    NSLayoutConstraint.activate([
      textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
      textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
      textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
    ])
    return cellView
  }

  private func makeShortcutCell(for shortcut: ShortcutRow, row: Int) -> NSView {
    let cellView = NSView()

    let recorder = ShortcutRecorderControl()
    recorder.currentShortcut = shortcut.combination
    recorder.translatesAutoresizingMaskIntoConstraints = false
    recorder.isEnabled = shortcut.isEnabled
    recorder.onRecordingComplete = { [weak self] combination in
      self?.assign(combination, to: shortcut.identifier)
    }
    cellView.addSubview(recorder)

    let resetButton = NSButton(
      image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset")!,
      target: self, action: #selector(resetShortcut(_:)))
    resetButton.bezelStyle = .rounded
    resetButton.isBordered = false
    resetButton.tag = row
    resetButton.isEnabled = shortcut.isEnabled
    resetButton.translatesAutoresizingMaskIntoConstraints = false
    cellView.addSubview(resetButton)

    NSLayoutConstraint.activate([
      recorder.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
      recorder.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      recorder.widthAnchor.constraint(equalToConstant: 150),
      recorder.heightAnchor.constraint(equalToConstant: 22),

      resetButton.leadingAnchor.constraint(equalTo: recorder.trailingAnchor, constant: 8),
      resetButton.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      resetButton.widthAnchor.constraint(equalToConstant: 24),
      resetButton.heightAnchor.constraint(equalToConstant: 24)
    ])
    return cellView
  }

  @objc private func resetShortcut(_ sender: NSButton) {
    guard shortcuts.indices.contains(sender.tag) else { return }
    let identifier = shortcuts[sender.tag].identifier
    assign(identifier.defaultCombination, to: identifier)
  }

  @objc private func resetAllShortcuts() {
    store.resetToDefaults()
  }

  @objc private func toggleEnabled(_ sender: NSButton) {
    let row = sender.tag
    guard shortcuts.indices.contains(row) else { return }

    store.setEnabled(sender.state == .on, for: shortcuts[row].identifier)
  }

  private func assign(_ combination: HotkeyCombination, to identifier: HotkeyIdentifier) {
    if let otherIdentifier = HotkeyIdentifier.allCases.first(where: {
      $0 != identifier && store.combination(for: $0).conflicts(with: combination)
    }) {
      NSSound.beep()
      // Recording results arrive inside the recorder's event tap; a modal alert there would stall input
      DispatchQueue.main.async {
        Alerts.showWarning(
          "Shortcut already in use", info: "This shortcut is already assigned to \(otherIdentifier.displayName).")
      }
      return
    }

    store.update(combination, for: identifier)
  }
}
