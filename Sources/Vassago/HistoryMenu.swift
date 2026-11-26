import AppKit
import VassagoEngine

/// The rows of the list, for the pop-up at the pointer and for the menu bar item.
final class HistoryMenu: NSObject {
    private let model: AppModel
    private var isOpen = false

    init(model: AppModel) {
        self.model = model
    }

    /// Opens the whole history at the mouse pointer. A menu leaves the keyboard focus with the app in front.
    func popUp() {
        // The hotkey still arrives while the list is open.
        guard !isOpen else { return }
        isOpen = true
        defer { isOpen = false }
        let menu = NSMenu()
        addPermissionRows(to: menu)
        addClips(to: menu, limit: .max)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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
