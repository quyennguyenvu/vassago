import AppKit
import Carbon
import VassagoEngine
import os

/// The app's one diagnostic log, and what its report reads at the moment it is copied.
/// Safe from any thread: the clipboard queue writes lines as well as the main thread.
///
/// A line never holds anything that was copied: no text, no title, no file name, no search.
/// It holds sizes, the names of clipboard types, the first 8 characters of a clip's id, and the bundle ids of apps.
enum Diagnostics {
    /// One thing that is true right now.
    struct Fact: Equatable {
        let name: String
        let value: String
        /// False marks what would explain a copy not recorded or a pick not pasted. Nil is neither good nor bad.
        let fine: Bool?
    }

    /// What the panel's diagnostics page shows: the state of this moment, and the lines newest first.
    struct Page: Equatable {
        let facts: [Fact]
        /// As the lines are stamped, to tell a line written today from an older one.
        let today: String
        let lines: [String]
    }

    /// Guards everything below it that both threads touch.
    private static let lock = NSLock()
    private static var log = DiagnosticLog()
    private static var lastLook = Date()
    private static var frontApp = "none"
    private static var lastApp = "none"

    private static var launched = Date()
    /// Main thread only.
    private static var secureInput = false
    private static let system = Logger(subsystem: "com.quyennguyenvu.vassago", category: "diagnostics")
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // To the millisecond: a copy, a pick and its paste are often within one second.
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// Called on the main thread after each line is written, so an open diagnostics page can show it.
    static var onNote: () -> Void = {}

    static func note(_ line: String) {
        let stamped = "\(clock.string(from: Date()))  \(line)"
        lock.withLock { log.note(stamped) }
        // Notice is the lowest level macOS keeps on disk. Public, or the line reads back as <private>.
        system.notice("\(line, privacy: .public)")
        DispatchQueue.main.async { onNote() }
    }

    /// Notes the launch, and starts watching for sleep, wake and the app in front.
    static func start() {
        launched = Date()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        note("[app] started \(UpdateCheck.current?.text ?? "dev") on macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · pid \(getpid())")
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            note("[app] going to sleep")
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            note("[app] woke from sleep")
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { notification in
            remember(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        remember(NSWorkspace.shared.frontmostApplication)
    }

    /// Called every two seconds on the main thread. While Secure Input is on, the open list gets no keys of its own.
    static func tick() {
        let on = IsSecureEventInputEnabled()
        guard on != secureInput else { return }
        secureInput = on
        note("[input] secure input \(secureInputNow())")
    }

    /// Called at every look at the clipboard. Returns the seconds since the look before it.
    static func looked(at time: Date) -> Double {
        lock.withLock {
            defer { lastLook = time }
            return time.timeIntervalSince(lastLook)
        }
    }

    /// The app in front, Vassago included: where a copy came from, and where a pick is pasted.
    static var front: String {
        lock.withLock { frontApp }
    }

    /// An error as its domain and code, which say what failed without quoting a path or a text.
    static func cause(_ error: Error) -> String {
        let error = error as NSError
        return "\(DiagnosticLog.clean(error.domain)) \(error.code)"
    }

    /// `facts` are the caller's; the watcher, Secure Input and the last app are added here.
    static func page(facts: [Fact]) -> Page {
        Page(facts: facts + ownFacts(), today: String(clock.string(from: Date()).prefix(10)), lines: lock.withLock { log.lines.reversed() })
    }

    /// The text the page's Copy button puts on the clipboard.
    static func report(settings: String, facts: [Fact]) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let up = Int(Date().timeIntervalSince(launched))
        let now = (facts + ownFacts()).map { "\($0.name.lowercased()) \($0.value)" }.joined(separator: " · ")
        return lock.withLock { log }.report(header: [
            "Vassago \(UpdateCheck.current?.text ?? "dev") · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · up \(up / 3600)h \(up / 60 % 60)m",
            "Settings: \(settings)",
            "Now: \(now)",
        ])
    }

    private static func ownFacts() -> [Fact] {
        let (idle, lastApp) = lock.withLock { (Date().timeIntervalSince(lastLook), lastApp) }
        let secure = secureInputNow()
        return [
            // The watcher looks every 0.3 seconds.
            Fact(name: "Watcher", value: idle < 3 ? "running" : "STALLED for \(Int(idle)) s", fine: idle < 3),
            Fact(name: "Secure Input", value: secure, fine: secure == "off"),
            Fact(name: "Last app", value: lastApp, fine: nil),
        ]
    }

    private static func remember(_ app: NSRunningApplication?) {
        guard let app else { return }
        let name = name(of: app.processIdentifier)
        lock.withLock {
            frontApp = name
            if app.processIdentifier != getpid() { lastApp = name }
        }
    }

    /// An app's bundle id; a process that is not an app is named by its executable.
    private static func name(of pid: pid_t) -> String {
        var name = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        if name.isEmpty {
            var buffer = [CChar](repeating: 0, count: 64)
            proc_name(pid, &buffer, UInt32(buffer.count))
            name = String(cString: buffer)
        }
        let cleaned = DiagnosticLog.clean(name)
        return cleaned.isEmpty ? "unknown" : cleaned
    }

    private static func secureInputNow() -> String {
        guard IsSecureEventInputEnabled() else { return "off" }
        // Not a documented key. Without it the report still says that Secure Input is on.
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        guard let holder = session?["kCGSSessionSecureInputPID"] as? pid_t else { return "ON" }
        return "ON (held by \(name(of: holder)))"
    }
}
