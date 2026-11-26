import AppKit
import VassagoEngine

/// The rows of the list, for the pop-up at the pointer and for the menu bar item.
final class HistoryMenu: NSObject {
    private let model: AppModel
    /// The pop-up, while it is open.
    private var list: NSMenu?
    /// The row a key picked, until the pop-up has closed.
    private var picked: NSMenuItem?

    init(model: AppModel) {
        self.model = model
    }

    /// Opens the whole history at the mouse pointer. A menu leaves the keyboard focus with the app in front.
    func popUp() {
        // The hotkey still arrives while the list is open.
        guard list == nil else { return }
        let menu = NSMenu()
        addPermissionRows(to: menu)
        addClips(to: menu, limit: .max)
        list = menu
        let tap = keyTap()
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        // Invalidating the tap also takes it off the run loop.
        if let tap { CFMachPortInvalidate(tap) }
        list = nil
        if let picked {
            self.picked = nil
            NSApp.sendAction(picked.action!, to: picked.target, from: picked)
        }
    }

    /// Takes the digit and Return keys while the pop-up is open. A row picked through the menu itself
    /// arrives only after the menu's closing animation, about a third of a second later.
    /// Nil without Accessibility: the menu's own key equivalents still pick, and a pick only copies then.
    private func keyTap() -> CFMachPort? {
        guard AXIsProcessTrusted(), let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
            callback: { _, type, event, context in
                let menu = Unmanaged<HistoryMenu>.fromOpaque(context!).takeUnretainedValue()
                return type == .keyDown && menu.take(event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        return tap
    }

    /// True when the key picked a row: the pop-up then closes at once, and `popUp` acts on the row.
    private func take(_ event: CGEvent) -> Bool {
        // With Command, Control or Option held, the key is left to the menu as before.
        guard let list, event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate]),
              let typed = NSEvent(cgEvent: event)?.charactersIgnoringModifiers, !typed.isEmpty else { return false }
        // Return and Enter pick the highlighted row; any other key picks the row it is the key equivalent of.
        let row = typed == "\r" || typed == "\u{3}" ? list.highlightedItem : list.items.first { $0.keyEquivalent == typed }
        guard let row, row.action != nil else { return false }
        picked = row
        list.cancelTrackingWithoutAnimation()
        return true
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
        for (index, clip) in model.clips.prefix(limit).enumerated() {
            let item = add(clip.title, #selector(pick(_:)), to: menu)
            // The nine newest are one digit away.
            if index < 9 {
                item.keyEquivalent = String(index + 1)
                item.keyEquivalentModifierMask = []
            }
            item.representedObject = clip.id
            item.image = model.thumbnail(of: clip)
        }
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func pick(_ item: NSMenuItem) {
        guard let clip = model.clips.first(where: { $0.id == item.representedObject as? String }) else { return }
        model.pick(clip, paste: true)
    }

    @objc private func openPanel() {
        model.openPanel()
    }

    @objc private func openAccessibilitySettings() {
        model.openAccessibilitySettings()
    }
}
