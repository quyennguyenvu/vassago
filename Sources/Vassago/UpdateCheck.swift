import VassagoEngine
import AppKit

/// Asks GitHub for the latest release. The app's only network request: at most once a day, and on demand.
enum UpdateCheck {
    /// Hardcoded on purpose: the page we open is built from this, never from the response.
    private static let repo = "quyennguyenvu/vassago"

    static var current: Version? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(Version.init)
    }

    /// Calls back on the main thread with the latest release's version, if the response named one,
    /// and with whether GitHub answered at all.
    static func latest(_ done: @escaping (_ latest: Version?, _ answered: Bool) -> Void) {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        URLSession.shared.dataTask(with: url) { data, response, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let latest = (json?["tag_name"] as? String).flatMap(Version.init)
            DispatchQueue.main.async { done(latest, response != nil) }
        }.resume()
    }

    static func releasePage(for version: Version) -> URL {
        URL(string: "https://github.com/\(repo)/releases/tag/v\(version.text)")!
    }

    /// The answer to a check the user asked for.
    static func report(latest: Version?) {
        let current = Self.current
        let alert = NSAlert()
        var page: URL?
        if let latest, let current, latest > current {
            alert.messageText = "Vassago \(latest.text) is available"
            alert.informativeText = "You have \(current.text)."
            alert.addButton(withTitle: "Open Release Page")
            alert.addButton(withTitle: "Later")
            page = releasePage(for: latest)
        } else if let latest, let current {
            alert.messageText = "Vassago is up to date"
            alert.informativeText = "You have \(current.text). The latest release is \(latest.text)."
        } else {
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = "GitHub could not be reached, or no release has been published yet."
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let page {
            NSWorkspace.shared.open(page)
        }
    }
}
