import AppKit
import VassagoEngine

/// The rows of the list, for the pop-up at the pointer and for the menu bar item.
final class HistoryMenu: NSObject {
    private let model: AppModel
    /// The pop-up, while it is open.
    private var list: NSMenu?
    /// The row a key picked, until the pop-up has closed.
    private var picked: NSMenuItem?
    /// The pop-up's first row, which shows the search. Nil without the key tap: nothing could be typed.
    private var searchRow: NSMenuItem?
    /// What has been typed since `/` started a search in the pop-up. Nil until then.
    private var query: String?
    /// The most a row's title may take, in points: about 39 characters. The list is then some 300 points
    /// wide. Uncut, a 60-character title made it over 560, a third of a 1920-point screen.
    private static let titleWidth: CGFloat = 240
    /// Each clip's title as cut for the list, by id. Measuring them again on every opening took 20 ms for 100 clips.
    private var cut: [String: String] = [:]

    init(model: AppModel) {
        self.model = model
    }

    /// Opens the whole history at the mouse pointer. A menu leaves the keyboard focus with the app in front.
    func popUp() {
        // The hotkey still arrives while the list is open.
        guard list == nil else {
            Diagnostics.note("[list] hotkey pressed while the list is open, ignored")
            return
        }
        let menu = NSMenu()
        addPermissionRows(to: menu)
        let tap = keyTap()
        // At the top, the one edge of a menu that stays put while a search hides rows.
        if tap != nil, !model.clips.isEmpty {
            searchRow = menu.addItem(withTitle: "Type / to search", action: nil, keyEquivalent: "")
            searchRow?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            menu.addItem(.separator())
        }
        addClips(to: menu, limit: .max)
        // Otherwise the list gets narrower each time a search hides its widest row.
        menu.minimumWidth = menu.size.width
        list = menu
        Diagnostics.note("[list] opened by the hotkey: \(model.clips.count) clips · key tap \(tap != nil ? "on" : AXIsProcessTrusted() ? "REFUSED by macOS" : "off, no Accessibility") · in front \(Diagnostics.front)")
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        // Invalidating the tap also takes it off the run loop.
        if let tap { CFMachPortInvalidate(tap) }
        Diagnostics.note("[list] closed: \(picked == nil ? "no row picked by key" : "a row picked by key")\(query == nil ? "" : " · after a search")")
        list = nil
        searchRow = nil
        query = nil
        if let picked {
            self.picked = nil
            NSApp.sendAction(picked.action!, to: picked.target, from: picked)
        }
    }

    /// Takes the keys that pick a row or type into the search while the pop-up is open. A row picked
    /// through the menu itself arrives only after the menu's closing animation, about a third of a second later.
    /// Nil without Accessibility: the menu's own key equivalents still pick, and a pick only copies then.
    private func keyTap() -> CFMachPort? {
        guard AXIsProcessTrusted(), let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
            callback: { _, type, event, context in
                let menu = Unmanaged<HistoryMenu>.fromOpaque(context!).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    Diagnostics.note("[list] macOS switched the key tap off (event \(type.rawValue)); the menu's own keys still pick")
                }
                return type == .keyDown && menu.take(event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        return tap
    }

    /// True when the key was used here and is kept from the menu: it picked a row or went into the search.
    private func take(_ event: CGEvent) -> Bool {
        guard let list, let key = NSEvent(cgEvent: event), let typed = key.characters else { return false }
        let shown = list.items.filter { $0.representedObject != nil && !$0.isHidden }
        switch ListKeys.keyPressed(typed, held: AppModel.modifiers(key.modifierFlags), searching: query != nil) {
        case .pick(let number):
            return close(picking: number <= shown.count ? shown[number - 1] : nil)
        case .pickCurrent:
            let highlighted = list.highlightedItem.flatMap { $0.isHidden ? nil : $0 }
            // No row can be highlighted from code, so Return on a search takes its top match.
            return close(picking: highlighted ?? (query == nil ? nil : shown.first))
        case .startSearch:
            guard searchRow != nil else { return false }
            query = ""
        case .type(let text):
            query?.append(text)
        case .erase:
            if query?.isEmpty == false { query?.removeLast() }
        case .pass:
            return false
        }
        showMatches()
        return true
    }

    /// True when there is such a row: the pop-up then closes at once, and `popUp` acts on the row.
    private func close(picking row: NSMenuItem?) -> Bool {
        guard let row, row.action != nil else { return false }
        picked = row
        list?.cancelTrackingWithoutAnimation()
        return true
    }

    /// Leaves only the clips whose title has the search text, numbered again from the top.
    private func showMatches() {
        guard let list, let query else { return }
        // A row's own title may be cut short, and the search is in the whole one.
        let titles = Dictionary(model.clips.map { ($0.id, $0.title) }) { first, _ in first }
        var shown = 0
        for row in list.items where row.representedObject != nil {
            row.isHidden = !matches(title: titles[row.representedObject as? String ?? ""] ?? row.title, query: query)
            if !row.isHidden { shown += 1 }
            row.keyEquivalent = !row.isHidden && shown <= 9 ? String(shown) : ""
            // A bare digit is typed into the search now, so the rows show ⌘1 to ⌘9.
            row.keyEquivalentModifierMask = .command
        }
        let text = "Search: \(query)" + (shown == 0 ? "  (no clip matches)" : "")
        searchRow?.title = text
        // In the label colour: a disabled row's plain title is dimmed, and this is what the user is typing.
        searchRow?.attributedTitle = NSAttributedString(
            string: text, attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.menuFont(ofSize: 0)])
    }

    /// A row for each missing permission, clipboard access first.
    func addPermissionRows(to menu: NSMenu) {
        let before = menu.numberOfItems
        if model.cannotRecord { add("Clipboard access is off…", #selector(openPanel), to: menu) }
        if !model.trusted { add("Grant Accessibility to paste directly…", #selector(openAccessibilitySettings), to: menu) }
        if menu.numberOfItems > before { menu.addItem(.separator()) }
    }

    /// The newest `limit` clips. Picking one pastes it into the app in front.
    func addClips(to menu: NSMenu, limit: Int) {
        if model.clips.isEmpty {
            // With no action the row is disabled.
            menu.addItem(withTitle: "Nothing copied yet", action: nil, keyEquivalent: "")
        }
        let font: NSFont = menu.font
        let kept = Set(model.clips.map(\.id))
        cut = cut.filter { kept.contains($0.key) }
        for (index, clip) in model.clips.prefix(limit).enumerated() {
            let image = model.thumbnail(of: clip)
            // A thumbnail and the gap after it come out of the same width.
            let room = Self.titleWidth - (image.map { $0.size.width + 8 } ?? 0)
            let title = cut[clip.id] ?? shortened(clip.title) { ($0 as NSString).size(withAttributes: [.font: font]).width <= room }
            cut[clip.id] = title
            let item = add(title, #selector(pick(_:)), to: menu)
            // The nine newest are one digit away.
            if index < 9 {
                item.keyEquivalent = String(index + 1)
                item.keyEquivalentModifierMask = []
            }
            item.representedObject = clip.id
            item.image = image
        }
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func pick(_ item: NSMenuItem) {
        guard let clip = model.clips.first(where: { $0.id == item.representedObject as? String }) else {
            Diagnostics.note("[pick] the row's clip is no longer in the history")
            return
        }
        model.pick(clip, paste: true)
    }

    @objc private func openPanel() {
        model.openPanel()
    }

    @objc private func openAccessibilitySettings() {
        model.openAccessibilitySettings()
    }
}
