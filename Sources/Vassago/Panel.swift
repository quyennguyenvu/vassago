import AppKit
import SwiftUI
import VassagoEngine

/// The control panel window. Closing it only hides it.
final class Panel: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let window: NSWindow

    init(model: AppModel) {
        self.model = model
        window = NSWindow(contentViewController: NSHostingController(rootView: PanelView(model: model)))
        super.init()
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = "Vassago"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Palette.bg0)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    func show() {
        // The Dock icon exists only while the panel is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // The panel opens on its settings next time, and an unseen page stops being refreshed.
        model.hideDiagnostics()
    }

    // A recording left running would keep the hotkey unregistered.
    func windowDidResignKey(_ notification: Notification) {
        model.cancelRecording()
    }
}

/// The dark tokens Agares and Goetia use.
private enum Palette {
    static let bg0 = rgb(0x0F1115)
    static let bg1 = rgb(0x161A20)
    static let bg2 = rgb(0x1E232B)
    static let border = rgb(0x2A303A)
    static let text1 = rgb(0xE7EAEF)
    static let text2 = rgb(0x9AA3AF)
    static let accent = rgb(0xFF9E2C)
    static let ok = rgb(0x34C77B)
    static let warn = rgb(0xF5A623)
    static let ember = LinearGradient(colors: [accent, rgb(0xE8590C)], startPoint: .topLeading, endPoint: .bottomTrailing)

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

private struct PanelView: View {
    @ObservedObject var model: AppModel

    private var shown: [Clip] {
        model.clips.filter { matches(title: $0.title, query: model.query) }
    }

    var body: some View {
        // The settings stay in place under the diagnostics page and keep setting the window's size,
        // so the window does not jump when the page opens or closes.
        settings
            .opacity(model.diagnostics == nil ? 1 : 0)
            .disabled(model.diagnostics != nil)
            .accessibilityHidden(model.diagnostics != nil)
            .overlay {
                if let page = model.diagnostics {
                    DiagnosticsPage(page: page, back: model.hideDiagnostics, copy: model.copyDiagnostics)
                }
            }
            .padding(EdgeInsets(top: 40, leading: 28, bottom: 24, trailing: 28))
            .frame(width: 420)
            .background(Palette.bg0)
            .foregroundColor(Palette.text1)
            .tint(Palette.accent)
    }

    private var settings: some View {
        VStack(spacing: 22) {
            Text("Vassago")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ember)
            // The limits share the switch's row, so the panel grows no taller (see the list's height below).
            HStack(spacing: 8) {
                Toggle("Keep clipboard history", isOn: $model.keepsHistory)
                    .toggleStyle(.checkbox)
                // The row measures 350 points at its narrowest, of the 364 there are.
                Spacer(minLength: 0)
                choice("Most clips kept", model.maxClips, AppModel.clipChoices, { "\($0) clips" }) {
                    model.setLimits(clips: $0, megabytes: model.maxMegabytes)
                }
                .help("Most clips kept. The oldest are deleted to stay under it.")
                choice("Most space the clips take", model.maxMegabytes, AppModel.megabyteChoices, { $0 < 1000 ? "\($0) MB" : "\($0 / 1000) GB" }) {
                    model.setLimits(clips: model.maxClips, megabytes: $0)
                }
                .help("Most space the clips take. The oldest are deleted to stay under it.")
            }
            HStack(spacing: 8) {
                // The pop-up has the same name for VoiceOver.
                Text("Clear the macOS clipboard").accessibilityHidden(true)
                Spacer(minLength: 0)
                choice("Clear the macOS clipboard", model.clearMinutes, AppModel.clearChoices, wait) { model.clearMinutes = $0 }
                    .help("Empties the clipboard once it has held the same thing this long. The clip stays in the history.")
            }
            hotkeySection
            historySection
            HStack {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Reset to Defaults…", action: model.resetSettings)
                    .controlSize(.small)
            }
            footer
        }
        // In the corner beside the name: the footer's rows are full while a permission is missing.
        .overlay(alignment: .topTrailing) {
            Button("Diagnostics ›", action: model.showDiagnostics)
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
    }

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("HOTKEY")
            HStack(spacing: 4) {
                ForEach(model.hotkey.keycaps, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .frame(minWidth: 16)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Palette.bg2)
                        .cornerRadius(6)
                }
            }
            .padding(5)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.ember, lineWidth: 1.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.hotkey.name)
            // In words as well: at this size ⌃, the Control key, is easily read as an arrow for Shift.
            Text("Press \(model.hotkey.name) to open the list.")
                .font(.system(size: 12))
                .foregroundColor(Palette.text2)
            HStack(spacing: 10) {
                Button(model.recording ? "Press the new shortcut…" : "Record…", action: model.record)
                    .disabled(model.recording)
                if model.recording {
                    note("Esc cancels")
                } else if model.hotkeyRefused {
                    note("macOS could not register that shortcut. The previous one stays.")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.bg1)
        .cornerRadius(10)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                heading("HISTORY")
                // In the heading's row, so the panel grows no taller (see the list's height below).
                TextField("Search", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    // The recorder lets a key without a modifier through, and it would be typed here.
                    .disabled(model.recording)
                Button("Clear All", action: model.clearHistory)
                    .disabled(model.clips.isEmpty)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown, id: \.id) { clip in
                        ClipRow(model: model, clip: clip)
                    }
                }
            }
            // Five rows: with eight the panel was 819 points tall, too tall for a 900-point screen with the Dock showing.
            .frame(height: 170)
            .overlay {
                if shown.isEmpty { note(model.clips.isEmpty ? "Nothing copied yet" : "No clip matches") }
            }
        }
        .padding(14)
        .background(Palette.bg1)
        .cornerRadius(10)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                dot(model.access == .allowed)
                if model.access == .allowed {
                    Text("Clipboard access allowed").foregroundColor(Palette.text2)
                } else {
                    Button("Allow Clipboard Access…", action: model.allowClipboardAccess)
                }
                Spacer()
            }
            if model.access != .allowed {
                Text("In the Settings page that opens, set Vassago to Always Allow under Paste from Other Apps.")
                    .foregroundColor(Palette.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                dot(model.trusted)
                if model.trusted {
                    Text("Accessibility granted").foregroundColor(Palette.text2)
                } else {
                    Button("Grant Accessibility…", action: model.openAccessibilitySettings)
                    Button("Reset Permission", action: model.resetPermission)
                }
                Spacer()
            }
            if !model.trusted {
                Text("Without it a pick only copies. Already switched on in Settings but still not working? Reset it, then grant again.")
                    .foregroundColor(Palette.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Vassago \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .foregroundColor(Palette.text2)
                if let version = model.availableVersion {
                    Text("\(version.text) available").foregroundColor(Palette.accent)
                    Spacer()
                    Button("Get \(version.text)…", action: model.openReleasePage)
                } else {
                    Spacer()
                    Button("Check for Updates…", action: model.checkForUpdates)
                }
            }
        }
        .font(.system(size: 12))
    }

    /// A small pop-up for one setting. The name is for VoiceOver.
    private func choice(_ name: String, _ value: Int, _ choices: [Int], _ label: @escaping (Int) -> String, set: @escaping (Int) -> Void) -> some View {
        Picker(name, selection: Binding(get: { value }, set: set)) {
            ForEach(choices, id: \.self) { Text(verbatim: label($0)).tag($0) }
        }
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }

    private func wait(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Never"
        case 1: return "After 1 minute"
        case 60: return "After 1 hour"
        default: return "After \(minutes) minutes"
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Palette.text2)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Palette.text2)
    }

    private func dot(_ ok: Bool) -> some View {
        Circle()
            .fill(ok ? Palette.ok : Palette.warn)
            .frame(width: 8, height: 8)
    }
}

/// What Vassago did and noticed going wrong, and what is true right now. Laid over the settings.
private struct DiagnosticsPage: View {
    let page: Diagnostics.Page
    let back: () -> Void
    let copy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button("‹ Back", action: back)
                Text("DIAGNOSTICS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Palette.text2)
                Spacer()
                Button("Copy", action: copy)
                    .help("Copies these lines, with the settings and the state above, as text.")
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(page.facts.indices, id: \.self) { index in
                    fact(page.facts[index])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Palette.bg1)
            .cornerRadius(10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(page.lines.indices, id: \.self) { index in
                        line(page.lines[index])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 12))
    }

    /// Amber marks what would explain a copy not recorded or a pick not pasted.
    private func fact(_ fact: Diagnostics.Fact) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(fact.fine.map { $0 ? Palette.ok : Palette.warn } ?? Color.clear)
                .frame(width: 7, height: 7)
            Text(fact.name).foregroundColor(Palette.text2)
            Text(fact.value).textSelection(.enabled)
        }
    }

    private func line(_ stored: String) -> some View {
        let parts = DiagnosticLog.parts(of: stored)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(parts?.stamp(today: page.today) ?? "")
                .foregroundColor(Palette.text2)
                // Room for a time to the millisecond, which is wider than an older line's day and minute.
                .frame(width: 84, alignment: .leading)
            (Text(parts.map { "[\($0.tag)] " } ?? "").foregroundColor(Palette.text2) + Text(parts?.text ?? stored))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11, design: .monospaced))
    }
}

/// One clip in the panel's list. A click copies it back; the × deletes it.
private struct ClipRow: View {
    @ObservedObject var model: AppModel
    let clip: Clip

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.pick(clip, paste: false)
            } label: {
                HStack(spacing: 8) {
                    if let thumbnail = model.thumbnail(of: clip) {
                        Image(nsImage: thumbnail)
                    }
                    Text(clip.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                // Without this only the drawn text takes clicks, not the rest of the row.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy to the clipboard")
            .accessibilityLabel("\(clip.title), \(clip.kind.rawValue)")
            Button {
                model.delete(clip)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Palette.text2)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(clip.title)")
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(model.copied == clip.id ? Palette.accent.opacity(0.25) : Color.clear)
        .cornerRadius(6)
        .animation(.easeOut(duration: 0.3), value: model.copied)
    }
}
