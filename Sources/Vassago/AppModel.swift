import AppKit
import Combine
import ServiceManagement
import VassagoEngine

/// The settings, state and actions that the menu bar item, the list and the panel share.
final class AppModel: ObservableObject {
    @Published var keepsHistory: Bool {
        didSet {
            UserDefaults.standard.set(keepsHistory, forKey: "keepsHistory")
            Diagnostics.note("[settings] history \(keepsHistory ? "on" : "off")")
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

    /// The limits the panel offers: clips kept, and megabytes their data may take.
    static let clipChoices = [25, 50, 100, 200, 500]
    static let megabyteChoices = [50, 100, 200, 500, 1000]
    /// Minutes the Mac's clipboard may hold the same thing before Vassago empties it. 0 never empties it.
    static let clearChoices = [0, 1, 5, 10, 30, 60]
    private static let standardClips = 100
    private static let standardMegabytes = 200

    @Published private(set) var maxClips: Int
    @Published private(set) var maxMegabytes: Int
    @Published var clearMinutes: Int {
        didSet {
            defaults.set(clearMinutes, forKey: "clearMinutes")
            Diagnostics.note("[settings] clear the clipboard \(clearMinutes == 0 ? "never" : "after \(clearMinutes) min")")
            clipboard.setClearing(afterMinutes: clearMinutes)
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

    /// What the diagnostics page shows while it is open; nil while the settings show.
    @Published private(set) var diagnostics: Diagnostics.Page?

    /// The clip a click in the panel has just copied, for a moment.
    @Published private(set) var copied: String?
    /// The text in the panel's search field. Here, not @State in the view: Command Line Tools ships no plugin for that macro.
    @Published var query = ""

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
        // A stored limit the panel does not offer could not be shown there, so the default takes its place.
        let stored = { (key: String, choices: [Int], standard: Int) in
            choices.contains(defaults.integer(forKey: key)) ? defaults.integer(forKey: key) : standard
        }
        maxClips = stored("maxClips", Self.clipChoices, Self.standardClips)
        maxMegabytes = stored("maxMegabytes", Self.megabyteChoices, Self.standardMegabytes)
        clearMinutes = stored("clearMinutes", Self.clearChoices, 0)
    }

    /// Loads the history, registers the hotkey, asks for the permissions once, and starts watching both.
    func start() {
        Diagnostics.onNote = { [weak self] in self?.refreshDiagnostics() }
        Diagnostics.note("[settings] \(settingsLine)")
        Diagnostics.note("[perm] clipboard access \(access.rawValue) · accessibility \(trusted ? "granted" : "missing")")
        clipboard.onChange = { [weak self] clips in
            guard let self else { return }
            self.clips = clips
            let kept = Set(clips.map(\.id))
            self.thumbnails = self.thumbnails.filter { kept.contains($0.key) }
        }
        clipboard.start(maxCount: maxClips, maxBytes: maxMegabytes * 1_000_000)
        clipboard.setClearing(afterMinutes: clearMinutes)
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
        if trusted != self.trusted {
            Diagnostics.note("[perm] accessibility \(trusted ? "granted" : "withdrawn")")
            self.trusted = trusted
        }
        let access = Clipboard.access
        if access != self.access {
            Diagnostics.note("[perm] clipboard access \(access.rawValue), was \(self.access.rawValue)")
            self.access = access
        }
        Diagnostics.tick()
        refreshDiagnostics()
        checkForUpdatesIfDue()
    }

    // MARK: Diagnostics

    func showDiagnostics() {
        diagnostics = Diagnostics.page(facts: facts)
    }

    func hideDiagnostics() {
        diagnostics = nil
    }

    /// Keeps an open page current. Called when a line is written and on every tick.
    private func refreshDiagnostics() {
        guard diagnostics != nil else { return }
        let page = Diagnostics.page(facts: facts)
        if page != diagnostics { diagnostics = page }
    }

    /// Puts the diagnostics report on the clipboard. It is not recorded in the history.
    func copyDiagnostics() {
        clipboard.put(text: Diagnostics.report(settings: settingsLine, facts: facts))
    }

    private var settingsLine: String {
        "history \(keepsHistory ? "on" : "off") · \(maxClips) clips · \(maxMegabytes) MB"
            + " · clear the clipboard \(clearMinutes == 0 ? "never" : "after \(clearMinutes) min")"
            + " · hotkey \(hotkey.name) · launch at login \(launchAtLogin ? "on" : "off")"
    }

    /// What is true right now, and whether each is as it should be.
    private var facts: [Diagnostics.Fact] {
        let megabytes = String(format: "%.1f", Double(clips.reduce(0) { $0 + $1.bytes }) / 1_000_000)
        let registered = globalHotkey.isRegistered
        return [
            Diagnostics.Fact(name: "Clipboard access", value: access.rawValue, fine: access == .allowed),
            Diagnostics.Fact(name: "Accessibility", value: trusted ? "granted" : "MISSING", fine: trusted),
            Diagnostics.Fact(
                name: "Hotkey", value: recording ? "being recorded" : registered ? hotkey.name : "\(hotkey.name) NOT REGISTERED",
                fine: recording || registered),
            Diagnostics.Fact(
                name: "History", value: "\(keepsHistory ? "on" : "OFF"), \(clips.count) of \(maxClips) clips, \(megabytes) of \(maxMegabytes) MB",
                fine: keepsHistory),
        ]
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
                let trusted = AXIsProcessTrusted()
                if trusted { Clipboard.pressPaste() }
                Diagnostics.note("[pick] \(trusted ? "pressed Command+V" : "not pasted, no Accessibility") · in front \(Diagnostics.front)")
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

    /// Asks first when clips have to go to fit the new limits: they cannot be brought back.
    func setLimits(clips maxClips: Int, megabytes maxMegabytes: Int) {
        let over = clipsOver(maxClips, maxMegabytes)
        if over > 0 {
            let alert = NSAlert()
            alert.messageText = over == 1 ? "Delete the oldest clip?" : "Delete the \(over) oldest clips?"
            alert.informativeText = "The history does not fit the new limit otherwise. This cannot be undone."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        applyLimits(maxClips, maxMegabytes)
    }

    /// How many of the oldest clips these limits would push out.
    private func clipsOver(_ maxClips: Int, _ maxMegabytes: Int) -> Int {
        var fitted = History(clips: clips)
        return fitted.limit(maxCount: maxClips, maxBytes: maxMegabytes * 1_000_000).count
    }

    private func applyLimits(_ maxClips: Int, _ maxMegabytes: Int) {
        self.maxClips = maxClips
        self.maxMegabytes = maxMegabytes
        defaults.set(maxClips, forKey: "maxClips")
        defaults.set(maxMegabytes, forKey: "maxMegabytes")
        Diagnostics.note("[settings] limits \(maxClips) clips · \(maxMegabytes) MB")
        clipboard.setLimits(maxCount: maxClips, maxBytes: maxMegabytes * 1_000_000)
    }

    /// Puts every setting in the panel back as a new install has it. Asks first, and says so when clips go with it.
    func resetSettings() {
        let over = clipsOver(Self.standardClips, Self.standardMegabytes)
        let alert = NSAlert()
        alert.messageText = "Reset all settings?"
        alert.informativeText = "Hotkey: \(Hotkey.standard.name). History: on, \(Self.standardClips) clips, \(Self.standardMegabytes) MB. "
            + "Clear the macOS clipboard: never. Launch at login: off. Permissions stay as they are. "
            + (over == 0 ? "No clip is deleted."
                : over == 1 ? "The oldest clip no longer fits and is deleted. This cannot be undone."
                : "The \(over) oldest clips no longer fit and are deleted. This cannot be undone.")
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Diagnostics.note("[settings] reset to defaults")
        keepsHistory = true
        applyLimits(Self.standardClips, Self.standardMegabytes)
        clearMinutes = 0
        hotkeyRefused = false
        // Registers the standard shortcut as a recording would, and keeps the current one if macOS refuses it.
        finishRecording(.standard)
        if launchAtLogin { setLaunchAtLogin(false) }
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
        Diagnostics.note("[hotkey] recording a new shortcut, \(hotkey.name) unregistered meanwhile")
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
        if captured == nil { Diagnostics.note("[hotkey] recording cancelled") }
        if let captured, globalHotkey.register(captured) {
            hotkey = captured
        } else {
            // Cancelled, or refused by macOS: the previous shortcut stays.
            hotkeyRefused = captured != nil
            _ = globalHotkey.register(hotkey)
        }
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> Modifiers {
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
            Diagnostics.note("[perm] accessibility reset: tccutil exited with \(reset.terminationStatus)")
        } catch {
            cleared = false
            Diagnostics.note("[perm] accessibility reset: tccutil did not run: \(Diagnostics.cause(error))")
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
            Diagnostics.note("[login] launch at login failed: \(Diagnostics.cause(error))")
            NSAlert(error: error).runModal()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        Diagnostics.note("[settings] launch at login \(launchAtLogin ? "on" : "off"), asked for \(on ? "on" : "off")")
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

/// True when a clip's title has the search text, whatever its case or accents. The panel and the list both search with it.
// shortcut: only the title is searched, not the text past a clip's first line; keep each clip's text in the index when a search misses for that.
func matches(title: String, query: String) -> Bool {
    // đ has no accent to strip, so the standard comparison keeps it apart from d.
    func folded(_ text: String) -> String {
        text.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
    }
    return query.isEmpty || folded(title).localizedStandardContains(folded(query))
}
