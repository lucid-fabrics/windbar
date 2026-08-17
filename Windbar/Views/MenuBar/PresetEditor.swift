import AppKit
import KeyboardShortcuts
import SwiftUI

/// Preset editor that takes over the whole device card while open: the
/// popover is only 320pt wide, so a sheet clips and a panel-in-panel reads
/// as clutter. The controls are the same StepSlider/SegmentedChips/Toggle
/// idioms the card itself uses, driven by the device's own `controlsConf`
/// schema, so editing a preset feels exactly like driving the fan, just
/// without sending anything until the preset fires.
struct PresetEditor: View {
    enum Mode: Equatable {
        /// Starts from the fan's current state.
        case create
        /// Starts from the preset's saved values.
        case edit(DevicePreset)
    }

    let device: DreoDevice
    let mode: Mode
    /// Names of the device's other presets, for duplicate-name blocking.
    let takenNames: [String]
    let allShortcutNames: [KeyboardShortcuts.Name]
    let onSave: (DevicePreset) -> Void
    let onCancel: () -> Void

    @State private var name: String
    // Not private: PresetEditorSections.swift's control renderers, in a
    // separate file, read and write the draft here.
    @State var values: [String: DreoValue]
    @State private var pickedShortcut: KeyboardShortcuts.Shortcut?
    @FocusState private var nameFieldFocused: Bool

    /// Fixed for the editor's lifetime, so the shortcut recorded here is the
    /// one the saved preset actually answers to.
    ///
    /// `@State`, not a stored `let`. SwiftUI rebuilds this struct on every
    /// pass of the parent's body, so a `let` assigned in `init` was a fresh
    /// UUID each time: one websocket temperature push while the editor was
    /// open moved the recorder to a name with nothing stored, the shortcut
    /// field went blank, and Save wrote a preset with no shortcut at all.
    @State private var presetID: UUID
    /// What the shortcut was before editing began. The recorder stores keys
    /// the moment they are typed, so Cancel has to put this back. Held in
    /// state for the same reason as the id: recomputing it against a new id
    /// would restore the wrong thing.
    @State private var originalShortcut: KeyboardShortcuts.Shortcut?
    private let isNew: Bool

    init(
        device: DreoDevice,
        mode: Mode,
        takenNames: [String],
        allShortcutNames: [KeyboardShortcuts.Name],
        onSave: @escaping (DevicePreset) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.device = device
        self.mode = mode
        self.takenNames = takenNames
        self.allShortcutNames = allShortcutNames
        self.onSave = onSave
        self.onCancel = onCancel

        let id: UUID
        switch mode {
        case .create:
            id = UUID()
            isNew = true
            _name = State(initialValue: "")
            _values = State(initialValue: Self.seed(for: device, preferring: device.state))
        case .edit(let preset):
            id = preset.id
            isNew = false
            _name = State(initialValue: preset.name)
            _values = State(initialValue: Self.seed(for: device, preferring: preset.values))
        }
        // Every initial value below is used on the first pass for this view's
        // identity only; later rebuilds discard them and keep what is stored.
        // The caller gives the editor an explicit `.id`, so opening a
        // different preset is a different identity and does start fresh.
        _presetID = State(initialValue: id)
        let stored = KeyboardShortcuts.getShortcut(for: .preset(id: id))
        _originalShortcut = State(initialValue: stored)
        _pickedShortcut = State(initialValue: stored)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.roomy) {
            header
            nameField
            controls
            if isShapeEmpty {
                fieldError("This device has nothing to save a preset from.")
            }
            shortcutField
            footer
        }
        // Same local-event-monitor constraint as every other recorder in
        // the popover: without an active app it opens but records nothing.
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            nameFieldFocused = true
        }
    }

    // MARK: - Fields

    /// The controls below are pixel-identical to the ones that drive the fan
    /// for real, so this has to say loudly which mode the card is in. A
    /// filled accent badge plus the "nothing is sent" line is what stops the
    /// user dragging the speed slider expecting the fan to answer.
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack(spacing: Theme.Space.tight) {
                HStack(spacing: 4) {
                    Image(systemName: isNew ? "plus" : "pencil")
                        .font(.system(size: 8.5, weight: .bold))
                    Text(isNew ? "New Preset" : "Editing Preset")
                        .font(Theme.Font.sectionLabel)
                        .tracking(0.7)
                        .textCase(.uppercase)
                }
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(Theme.accent))

                Spacer(minLength: Theme.Space.tight)

                Text(device.deviceName)
                    .font(Theme.Font.deviceMeta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text("Set the shape you want saved. Nothing is sent until the preset runs, "
                 + "and running it turns the fan on.")
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            TextField("Name, e.g. Direction North", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Font.body)
                .focused($nameFieldFocused)
                .onSubmit(commit)
            if isDuplicateName {
                fieldError("Another preset already uses this name.")
            }
        }
    }

    private var shortcutField: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack(spacing: Theme.Space.tight) {
                Text("Shortcut")
                    .font(Theme.Font.body)
                Spacer(minLength: Theme.Space.tight)
                KeyboardShortcuts.Recorder(for: .preset(id: presetID)) { newValue in
                    pickedShortcut = newValue
                }
                .controlSize(.small)
            }
            if let collision {
                fieldError("Conflicts with \(collision.conflictingName.displayDescription).")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Space.tight) {
            Spacer(minLength: 0)
            Button("Cancel", action: cancel)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            Button("Save", action: commit)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }

    private func fieldError(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.tight) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text(message)
                .font(Theme.Font.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.danger)
    }

    // MARK: - Validation and commit

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicateName: Bool {
        let candidate = trimmedName.lowercased()
        guard !candidate.isEmpty else { return false }
        return takenNames.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == candidate }
    }

    private var collision: ShortcutCollision? {
        guard let picked = pickedShortcut else { return nil }
        return ShortcutRegistry.findCollision(
            proposed: picked,
            excluding: .preset(id: presetID),
            candidates: allShortcutNames
        )
    }

    /// An empty shape is a preset that would apply nothing but power and
    /// could never be told apart from every other empty preset, and it can
    /// never be turned off by firing it again either: `isActive` treats an
    /// empty shape as never active on purpose, so pressing its key would
    /// just turn the fan on, over and over, with no way back to off from the
    /// same key. A device with nothing to seed only reaches this editor if
    /// its schema is genuinely empty, at which point there is nothing a
    /// preset on it could mean.
    private var isShapeEmpty: Bool {
        values.isEmpty
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isDuplicateName && !isShapeEmpty && collision == nil
    }

    private func commit() {
        guard canSave else { return }
        onSave(DevicePreset(id: presetID, name: trimmedName, values: values))
    }

    private func cancel() {
        // The recorder persists keystrokes immediately, so an abandoned edit
        // has to restore what was there before (nil for a new preset).
        KeyboardShortcuts.setShortcut(isNew ? nil : originalShortcut, for: .preset(id: presetID))
        onCancel()
    }

    /// The set of commands a preset stores: everything the device's control
    /// schema can render, and nothing else. Seeding from this list keeps
    /// wire junk like `connected` or module fields out of the preset, so
    /// applying one never sends a command the fan didn't ask for. Power is
    /// excluded on purpose: running a preset turns the fan on, so a shape
    /// never carries its own on/off.
    private static func seed(
        for device: DreoDevice,
        preferring preferred: [String: DreoValue]
    ) -> [String: DreoValue] {
        var cmds: Set<String> = []
        for section in device.controlsConf?.control ?? [] {
            if let cmd = section.cmd { cmds.insert(cmd) }
            for item in section.items ?? [] { cmds.insert(item.cmd) }
        }

        cmds.remove(device.powerKey)

        var seeded: [String: DreoValue] = [:]
        for cmd in cmds {
            if let value = preferred[cmd] ?? device.state[cmd] {
                seeded[cmd] = value
            }
        }
        return seeded
    }
}
