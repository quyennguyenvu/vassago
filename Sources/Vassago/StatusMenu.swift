import AppKit
import CoreServices

/// The menu bar item, the Dock behaviour, and the rule that only the menu bar item can quit the app.
final class StatusMenu: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private lazy var panel = Panel(model: model)
    private lazy var historyMenu = HistoryMenu(model: model)
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var quitFromMenu = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading
        NSApp.mainMenu = Self.mainMenu()

        model.stateChanged = { [weak self] in self?.refreshTitle() }
        model.onHotkey = { [weak self] in self?.historyMenu.popUp() }
        model.openPanel = { [weak self] in self?.panel.show() }
        Diagnostics.start()
        model.start()
        refreshTitle()
        if model.cannotRecord || !model.trusted { panel.show() }
    }

    private func refreshTitle() {
        // The warning replaces the symbol while nothing can be recorded; the dot says a newer release is waiting.
        let symbol = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Vassago")
        statusItem.button?.image = model.cannotRecord ? nil : symbol
        statusItem.button?.title = (model.cannotRecord ? "⚠" : "") + (model.availableVersion == nil ? "" : " •")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        historyMenu.addPermissionRows(to: menu)
        if let version = model.availableVersion {
            add("Version \(version.text) Available…", #selector(openReleasePage), to: menu)
            menu.addItem(.separator())
        }
        historyMenu.addClips(to: menu, limit: 9)
        menu.addItem(.separator())
        add("Open Vassago…", #selector(openPanel), to: menu)
        add("Clear History…", #selector(clearHistory), to: menu)
        add("Check for Updates…", #selector(checkForUpdates), to: menu)
        add("Diagnostics…", #selector(openDiagnostics), to: menu)
        menu.addItem(.separator())
        add("Quit Vassago", #selector(quit), to: menu)
    }

    private func add(_ title: String, _ action: Selector, to menu: NSMenu) {
        menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
    }

    @objc private func openPanel() {
        panel.show()
    }

    @objc private func clearHistory() {
        model.clearHistory()
    }

    @objc private func checkForUpdates() {
        model.checkForUpdates()
    }

    @objc private func openDiagnostics() {
        model.showDiagnostics()
        panel.show()
    }

    @objc private func openReleasePage() {
        model.openReleasePage()
    }

    @objc private func quit() {
        quitFromMenu = true
        NSApp.terminate(nil)
    }

    // MARK: Dock and quitting

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitFromMenu || Self.systemIsShuttingDown() {
            // In the unified log, a start with no quit before it was a crash or a force-quit.
            Diagnostics.note("[app] quitting")
            return .terminateNow
        }
        // The Dock's Quit, like any other request to quit, only puts the panel away.
        panel.close()
        return .terminateCancel
    }

    /// Logout, restart and shutdown must still be able to quit the app.
    private static func systemIsShuttingDown() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        guard let reason = event?.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue else { return false }
        let systemWide = [kAELogOut, kAEReallyLogOut, kAERestart, kAEShutDown, kAEShowRestartDialog, kAEShowShutdownDialog]
        return systemWide.map { OSType($0) }.contains(reason)
    }

    /// No Quit item on purpose.
    private static func mainMenu() -> NSMenu {
        let app = NSMenu()
        app.addItem(withTitle: "Hide Vassago", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Close Panel", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        // With no Quit item, ⌘Q would do nothing at all. An unlisted second shortcut makes it close the panel.
        let alsoClose = app.addItem(withTitle: "Close Panel", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "q")
        alsoClose.isHidden = true
        alsoClose.allowsKeyEquivalentWhenHidden = true

        // The panel's search field gets ⌘X, ⌘C, ⌘V and ⌘A only through a menu.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let main = NSMenu()
        for menu in [app, edit] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        return main
    }
}
