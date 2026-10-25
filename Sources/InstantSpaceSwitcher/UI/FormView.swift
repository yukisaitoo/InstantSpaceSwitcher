import AppKit

final class FormView: NSView {
  private let gridView = NSGridView()

  init() {
    super.init(frame: .zero)
    gridView.translatesAutoresizingMaskIntoConstraints = false
    gridView.columnSpacing = 16
    gridView.rowSpacing = 12
    addSubview(gridView)

    NSLayoutConstraint.activate([
      gridView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
      gridView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      gridView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
      gridView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func addRow(title: String, control: NSView) {
    addRow(label: NSTextField(labelWithString: title), control: control)
  }

  func addRow(label: NSView?, control: NSView) {
    let row = gridView.addRow(with: [label ?? NSView(), control])
    row.cell(at: 0).xPlacement = .trailing
    row.cell(at: 1).xPlacement = .leading
    row.cell(at: 0).yPlacement = .center
    row.cell(at: 1).yPlacement = .center
  }

  func addSectionSpacing() {
    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    spacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
    gridView.addRow(with: [spacer, NSView()])
  }
}
