import AppKit
import Combine
import ServiceManagement
import VassagoEngine

/// The settings, state and actions that the menu bar item, the list and the panel share.
final class AppModel: ObservableObject {
    @Published var keepsHistory: Bool {
        didSet {
            UserDefaults.standard.set(keepsHistory, forKey: "keepsHistory")
            if keepsHistory, access == .neverAsked { clipboard.ask() }
            refreshRecording()
            stateChanged()
        }
    }

    @Published private(set) var hotkey: Hotkey {
        didSet {
            UserDefaults.standard.set(Int(hotkey.modifiers.rawValue), forKey: "hotkeyModifiers")
            UserDefaults.standard.set(Int(hotkey.keyCode), forKey: "hotkeyKeyCode")
        }
    }

    /// The history, newest first.
    @Published private(set) var clips: [Clip] = []

    @Published private(set) var access = Clipboard.access {
        didSet {
            refreshRecording()
            stateChanged()
        }
    }

    /// Accessibility is granted, so a pick can press Command+V.
    @Published private(set) var trusted = AXIsProcessTrusted()
    /// The next shortcut pressed in the panel becomes the hotkey.
    @Published private(set) var recording = false
    /// macOS would not register the shortcut just recorded.
    @Published private(set) var hotkeyRefused = false
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// A release newer than the running app, once a check has found one.
    @Published private(set) var availableVersion: Version? {
        didSet { stateChanged() }
    }

    /// The clip a click in the panel has just copied, for a moment.
    @Published private(set) var copied: String?

    /// Called on the main thread when what the menu bar item shows has changed.
    var stateChanged: () -> Void = {}
    var onHotkey: () -> Void = {}
    var openPanel: () -> Void = {}

    /// The history is switched on, but macOS does not let Vassago read the clipboard.
    var cannotRecord: Bool {
        keepsHistory && access != .allowed
    }

    private let defaults = UserDefaults.standard
    private let clipboard = Clipboard()
    private let globalHotkey = GlobalHotkey()
    private var recorder: Any?
    private var thumbnails: [String: NSImage] = [:]

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["keepsHistory": true])
        keepsHistory = defaults.bool(forKey: "keepsHistory")
        hotkey = Self.storedHotkey(in: defaults)
    }

    /// Loads the history, registers the hotkey, asks for the permissions once, and starts watching both.
    func start() {
        clipboard.onChange = { [weak self] clips in
            guard let self else { return }
            self.clips = clips
            let kept = Set(clips.map(\.id))
            self.thumbnails = self.thumbnails.filter { kept.contains($0.key) }
        }
        clipboard.start()
        globalHotkey.onPress = { [weak self] in self?.onHotkey() }
        hotkeyRefused = !globalHotkey.register(hotkey)
        requestAccessibility()
        if keepsHistory, access == .neverAsked { clipboard.ask() }
        refreshRecording()
        checkForUpdatesIfDue()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// Both permissions can change in System Settings at any time, so they are read again here.
    private func tick() {
        let trusted = AXIsProcessTrusted()
        if trusted != self.trusted { self.trusted = trusted }
        let access = Clipboard.access
        if access != self.access { self.access = access }
        checkForUpdatesIfDue()
    }

    private func refreshRecording() {
        clipboard.setRecording(keepsHistory && access == .allowed)
    }

    // MARK: The history

    /// Puts the clip on the clipboard. From a list outside the panel it is then pasted into the app in front.
    func pick(_ clip: Clip, paste: Bool) {
        clipboard.put(clip) { [weak self] found in
            guard found else {
                NSSound.beep()
                return
            }
            if paste {
                if AXIsProcessTrusted() { Clipboard.pressPaste() }
            } else {
                self?.flash(clip.id)
            }
        }
    }

    private func flash(_ id: String) {
        copied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if self?.copied == id { self?.copied = nil }
        }
    }

    func delete(_ clip: Clip) {
        clipboard.delete(clip)
    }

    /// Asks first: the clips cannot be brought back.
    func clearHistory() {
        guard !clips.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Clear the clipboard history?"
        alert.informativeText = clips.count == 1 ? "The clip is deleted. This cannot be undone." : "All \(clips.count) clips are deleted. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { clipboard.clear() }
    }

    /// The picture in front of an image or files row, sized to fit 64 × 32 points.
    func thumbnail(of clip: Clip) -> NSImage? {
        guard clip.kind != .text else { return nil }
        if let cached = thumbnails[clip.id] { return cached }
        guard let image = NSImage(contentsOf: Store.thumbnail(of: clip.id)), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(64 / image.size.width, 32 / image.size.height, 1)
        image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        thumbnails[clip.id] = image
        return image
    }

    // MARK: The hotkey

    /// The next shortcut pressed in the panel becomes the hotkey. Escape, or leaving the panel, cancels.
    func record() {
        guard !recording else { return }
        recording = true
        hotkeyRefused = false
        // Unregistered meanwhile, so that pressing the current shortcut can be captured too.
        globalHotkey.unregister()
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch HotkeyRecorder.keyPressed(event.keyCode, held: Self.modifiers(event.modifierFlags)) {
            case .pending: return event
            case .cancelled: self.finishRecording(nil)
            case .captured(let hotkey): self.finishRecording(hotkey)
            }
            return nil
        }
    }

    func cancelRecording() {
        if recording { finishRecording(nil) }
    }

    private func finishRecording(_ captured: Hotkey?) {
        if let recorder { NSEvent.removeMonitor(recorder) }
        recorder = nil
        recording = false
        if let captured, globalHotkey.register(captured) {
            hotkey = captured
        } else {
            // Cancelled, or refused by macOS: the previous shortcut stays.
            hotkeyRefused = captured != nil
            _ = globalHotkey.register(hotkey)
        }
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> Modifiers {
        var held: Modifiers = []
        if flags.contains(.control) { held.insert(.control) }
        if flags.contains(.option) { held.insert(.option) }
        if flags.contains(.shift) { held.insert(.shift) }
        if flags.contains(.command) { held.insert(.command) }
        return held
    }

    private static func storedHotkey(in defaults: UserDefaults) -> Hotkey {
        guard defaults.object(forKey: "hotkeyKeyCode") != nil else { return .standard }
        let stored = Hotkey(
            modifiers: Modifiers(rawValue: UInt8(truncatingIfNeeded: defaults.integer(forKey: "hotkeyModifiers"))),
            keyCode: UInt16(truncatingIfNeeded: defaults.integer(forKey: "hotkeyKeyCode")))
        return stored.isValid ? stored : .standard
    }

    // MARK: Permissions

    /// Opens the Settings pane where the user picks Always Allow for Vassago.
    func allowClipboardAccess() {
        // macOS lists Vassago there only after it has asked once.
        if access == .neverAsked { clipboard.ask() }
        NSWorkspace.shared.open(Clipboard.settingsPane)
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Clears a grant left behind by a build from another signer, which macOS still lists as
    /// switched on but no longer honours, then asks again.
    func resetPermission() {
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.quyennguyenvu.vassago"]
        var cleared = false
        do {
            try reset.run()
            reset.waitUntilExit()
            cleared = reset.terminationStatus == 0
        } catch {
            cleared = false
        }
        if !cleared {
            let alert = NSAlert()
            alert.messageText = "Couldn't reset the permission"
            alert.informativeText = "In System Settings → Privacy & Security → Accessibility, select Vassago, remove it with the − button, then grant it again."
            alert.runModal()
        }
        requestAccessibility()
        openAccessibilitySettings()
    }

    /// Shows the system prompt if Accessibility is not granted, and lists Vassago in System Settings.
    private func requestAccessibility() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(prompt)
    }

    // MARK: Launch at login and updates

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// A check the user asked for: always answered with an alert.
    func checkForUpdates() {
        UpdateCheck.latest { [weak self] latest, _ in
            self?.note(latest)
            UpdateCheck.report(latest: latest)
        }
    }

    func openReleasePage() {
        guard let availableVersion else { return }
        NSWorkspace.shared.open(UpdateCheck.releasePage(for: availableVersion))
    }

    /// The quiet daily check. It only switches the update dot and the "available" lines on or off.
    private func checkForUpdatesIfDue() {
        let now = Date().timeIntervalSince1970
        guard now >= defaults.double(forKey: "nextUpdateCheck") else { return }
        // Booked an hour ahead first, so a check that gets no answer is retried then, not on every tick.
        defaults.set(now + 3600, forKey: "nextUpdateCheck")
        UpdateCheck.latest { [weak self] latest, answered in
            self?.note(latest)
            if answered { self?.defaults.set(Date().timeIntervalSince1970 + 86_400, forKey: "nextUpdateCheck") }
        }
    }

    /// A check that named no version leaves what is already known alone.
    private func note(_ latest: Version?) {
        guard let latest, let current = UpdateCheck.current else { return }
        availableVersion = latest > current ? latest : nil
    }
}
