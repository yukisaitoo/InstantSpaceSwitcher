import AppKit
import Combine

final class KeyboardShortcutsViewController: NSViewController {
  private enum Column {
    static let enabled = NSUserInterfaceItemIdentifier("enabled")
    static let name = NSUserInterfaceItemIdentifier("name")
    static let shortcut = NSUserInterfaceItemIdentifier("shortcut")
  }

  private let store = HotkeyStore.shared
  private var cancellables = Set<AnyCancellable>()

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    setupTableView()
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

  private func bindStore() {
    store.$hotkeys.combineLatest(store.$enabledStates)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.tableView.reloadData() }
      .store(in: &cancellables)
  }
}

extension KeyboardShortcutsViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    HotkeyIdentifier.allCases.count
  }
}

extension KeyboardShortcutsViewController: NSTableViewDelegate {
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let column = tableColumn?.identifier else { return nil }
    let identifier = HotkeyIdentifier.allCases[row]

    switch column {
    case Column.enabled: return makeEnabledCell(for: identifier, row: row)
    case Column.name: return makeNameCell(for: identifier)
    case Column.shortcut: return makeShortcutCell(for: identifier)
    default: return nil
    }
  }

  private func makeEnabledCell(for identifier: HotkeyIdentifier, row: Int) -> NSView {
    let cellView = NSTableCellView()
    let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
    checkbox.state = store.isEnabled(identifier) ? .on : .off
    checkbox.tag = row
    checkbox.translatesAutoresizingMaskIntoConstraints = false
    cellView.addSubview(checkbox)

    NSLayoutConstraint.activate([
      checkbox.centerXAnchor.constraint(equalTo: cellView.centerXAnchor),
      checkbox.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
    ])
    return cellView
  }

  private func makeNameCell(for identifier: HotkeyIdentifier) -> NSView {
    let cellView = NSTableCellView()
    let textField = NSTextField(labelWithString: identifier.displayName)
    textField.translatesAutoresizingMaskIntoConstraints = false
    textField.textColor = store.isEnabled(identifier) ? .labelColor : .disabledControlTextColor
    cellView.addSubview(textField)
    cellView.textField = textField

    NSLayoutConstraint.activate([
      textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
      textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
      textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
    ])
    return cellView
  }

  private func makeShortcutCell(for identifier: HotkeyIdentifier) -> NSView {
    let cellView = NSView()
    let recorder = ShortcutRecorderControl()
    recorder.currentShortcut = store.combination(for: identifier)
    recorder.translatesAutoresizingMaskIntoConstraints = false
    recorder.isEnabled = store.isEnabled(identifier)
    recorder.onRecordingComplete = { [weak self] combination in
      self?.assign(combination, to: identifier)
    }
    cellView.addSubview(recorder)

    NSLayoutConstraint.activate([
      recorder.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
      recorder.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      recorder.widthAnchor.constraint(equalToConstant: 150),
      recorder.heightAnchor.constraint(equalToConstant: 22)
    ])
    return cellView
  }

  @objc private func resetAllShortcuts() {
    store.resetToDefaults()
  }

  @objc private func toggleEnabled(_ sender: NSButton) {
    store.setEnabled(sender.state == .on, for: HotkeyIdentifier.allCases[sender.tag])
  }

  private func assign(_ combination: HotkeyCombination, to identifier: HotkeyIdentifier) {
    if let otherIdentifier = HotkeyIdentifier.allCases.first(where: {
      $0 != identifier && store.combination(for: $0).conflicts(with: combination)
    }) {
      NSSound.beep()
      // Recording results arrive inside the recorder's key monitor; don't run a modal alert from there
      DispatchQueue.main.async {
        Alerts.showWarning(
          "Shortcut already in use", info: "This shortcut is already assigned to \(otherIdentifier.displayName).")
      }
      return
    }

    store.update(combination, for: identifier)
  }
}
