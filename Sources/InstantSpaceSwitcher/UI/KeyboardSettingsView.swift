import SwiftUI

struct KeyboardSettingsView: View {
  private struct PendingShortcut {
    let combination: HotkeyCombination
    let identifier: HotkeyIdentifier
  }

  @ObservedObject private var store = HotkeyStore.shared
  @ObservedObject private var manager = HotkeyManager.shared

  /// The other shortcut that already uses the recorded keys
  @State private var conflict: HotkeyIdentifier?
  @State private var takenBySystem: PendingShortcut?
  @State private var failed: (identifier: HotkeyIdentifier, issue: HotkeyManager.Issue)?

  var body: some View {
    Form {
      Section {
        ForEach(HotkeyIdentifier.allCases, id: \.self, content: row)
      } footer: {
        HStack {
          Spacer()
          Button("Reset All to Defaults", action: store.resetToDefaults)
        }
      }
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .frame(width: 500)
    .fixedSize(horizontal: false, vertical: true)
    .alert("Shortcut already in use", isPresented: Binding(isPresent: $conflict), presenting: conflict) { _ in
    } message: { other in
      Text("This shortcut is already assigned to \(other.displayName).")
    }
    .alert(
      "macOS already uses this shortcut", isPresented: Binding(isPresent: $takenBySystem), presenting: takenBySystem
    ) { pending in
      Button("Use Anyway") { store.update(pending.combination, for: pending.identifier) }
      Button("Cancel", role: .cancel) {}
    }
    .alert(
      failed.map { "\($0.identifier.displayName): \($0.issue.message)" } ?? "",
      isPresented: Binding(isPresent: $failed)
    ) {}
    // Only problems that appear while Settings is open, i.e. caused by a change made here
    .onChange(of: manager.issues) { old, new in
      if let (identifier, issue) = new.first(where: { old[$0.key] != $0.value }) {
        failed = (identifier, issue)
      }
    }
  }

  private func row(_ identifier: HotkeyIdentifier) -> some View {
    HStack {
      Toggle(
        identifier.displayName,
        isOn: Binding(get: { store.isEnabled(identifier) }, set: { store.setEnabled($0, for: identifier) })
      )
      .toggleStyle(.checkbox)
      .labelsHidden()
      Text(identifier.displayName)
        .foregroundStyle(store.isEnabled(identifier) ? .primary : .secondary)
      Spacer()
      ShortcutRecorder(
        title: identifier.displayName,
        combination: store.combination(for: identifier),
        isEnabled: store.isEnabled(identifier)
      ) { record($0, for: identifier) }
      .fixedSize()
    }
  }

  private func record(_ combination: HotkeyCombination, for identifier: HotkeyIdentifier) {
    if let other = HotkeyIdentifier.allCases.first(where: { $0 != identifier && store.combination(for: $0) == combination }) {
      conflict = other
    } else if combination != store.combination(for: identifier), combination.isTakenBySystem {
      takenBySystem = PendingShortcut(combination: combination, identifier: identifier)
    } else {
      store.update(combination, for: identifier)
    }
  }
}
