import CryptoKit
import Foundation
import VassagoEngine

/// A clip's data as it sat on the clipboard: for each clipboard item, its types and their data.
typealias Payload = [[String: Data]]

/// The files under ~/Library/Application Support/Vassago. Used only on the clipboard queue,
/// apart from `thumbnail(of:)`, which only builds a path.
final class Store {
    private static let clips = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Vassago/clips", isDirectory: true)
    private static let index = clips.deletingLastPathComponent().appendingPathComponent("index.json")

    private let files = FileManager.default

    init() {
        try? files.createDirectory(at: Self.clips, withIntermediateDirectories: true)
        // Only this account may read what was copied.
        try? files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.clips.deletingLastPathComponent().path)
    }

    static func thumbnail(of id: String) -> URL {
        clips.appendingPathComponent(id + ".png")
    }

    private static func data(of id: String) -> URL {
        clips.appendingPathComponent(id + ".plist")
    }

    /// The clips kept from the last run, less those whose data is gone. Files that no clip names are deleted.
    func load() -> [Clip] {
        let index = (try? Data(contentsOf: Self.index)).flatMap { try? JSONDecoder().decode([Clip].self, from: $0) } ?? []
        // A folder that cannot be listed is left alone, not taken for empty.
        guard let names = try? files.contentsOfDirectory(atPath: Self.clips.path) else { return index }
        let kept = reconcile(index: index, files: Set(names))
        for name in kept.strays {
            try? files.removeItem(at: Self.clips.appendingPathComponent(name))
        }
        return kept.clips
    }

    /// False when the data could not be written. Nothing is left behind then.
    func write(_ payload: Payload, thumbnail: Data?, id: String) -> Bool {
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
            try data.write(to: Self.data(of: id), options: .atomic)
            try thumbnail?.write(to: Self.thumbnail(of: id), options: .atomic)
            return true
        } catch {
            delete([id])
            return false
        }
    }

    func save(_ clips: [Clip]) {
        guard let data = try? JSONEncoder().encode(clips) else { return }
        try? data.write(to: Self.index, options: .atomic)
    }

    func delete(_ ids: [String]) {
        for id in ids {
            try? files.removeItem(at: Self.data(of: id))
            try? files.removeItem(at: Self.thumbnail(of: id))
        }
    }

    func payload(of id: String) -> Payload? {
        guard let data = try? Data(contentsOf: Self.data(of: id)) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? Payload
    }

    /// The same for two copies of the same content, whatever order their types came in.
    static func digest(of payload: Payload) -> String {
        var hash = SHA256()
        for item in payload {
            for type in item.keys.sorted() {
                hash.update(data: Data(type.utf8))
                hash.update(data: item[type]!)
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
