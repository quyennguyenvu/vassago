/// One recorded copy. Its data is on disk; this is what the list needs to draw it.
public struct Clip: Codable, Equatable {
    public enum Kind: String, Codable {
        case text, image, files
    }

    /// Names the clip's files on disk.
    public let id: String
    public let kind: Kind
    /// The line the list shows.
    public let title: String
    /// Size of the clip's data.
    public let bytes: Int
    /// Equal digests mean equal content.
    public let digest: String

    public init(id: String, kind: Kind, title: String, bytes: Int, digest: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.bytes = bytes
        self.digest = digest
    }
}

/// The clips, newest first, held to a count and a total size.
public struct History {
    public private(set) var clips: [Clip]
    private var maxCount: Int
    private var maxBytes: Int

    public init(clips: [Clip] = [], maxCount: Int = 100, maxBytes: Int = 200_000_000) {
        self.clips = clips
        self.maxCount = maxCount
        self.maxBytes = maxBytes
    }

    /// Puts the clip on top. Returns the clips it pushed out, whose files are to be deleted:
    /// an older copy of the same content, then the oldest clips over a limit.
    public mutating func add(_ clip: Clip) -> [Clip] {
        let dropped = clips.filter { $0.digest == clip.digest }
        clips.removeAll { $0.digest == clip.digest }
        clips.insert(clip, at: 0)
        return dropped + trim()
    }

    /// Sets new limits. Returns the clips now over them, oldest first, whose files are to be deleted.
    public mutating func limit(maxCount: Int, maxBytes: Int) -> [Clip] {
        self.maxCount = maxCount
        self.maxBytes = maxBytes
        return trim()
    }

    private mutating func trim() -> [Clip] {
        var dropped: [Clip] = []
        // The newest clip stays, whatever its size.
        while clips.count > 1, clips.count > maxCount || clips.reduce(0, { $0 + $1.bytes }) > maxBytes {
            dropped.append(clips.removeLast())
        }
        return dropped
    }

    public mutating func remove(id: String) -> Clip? {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return nil }
        return clips.remove(at: index)
    }

    public mutating func removeAll() -> [Clip] {
        defer { clips = [] }
        return clips
    }
}

/// The line the list shows for a text clip: its first line that is not empty, with each run of
/// whitespace as one space, at most 60 characters.
public func title(forText text: String) -> String {
    let line = text.split(whereSeparator: \.isNewline)
        .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        .first { !$0.isEmpty } ?? ""
    return line.count > 60 ? String(line.prefix(59)) + "…" : line
}

/// The title as the list draws it: whole when it fits, otherwise its longest beginning that fits with … after it.
/// A menu is as wide as its widest row, so this is what keeps the list narrow. `fits` is asked about a
/// handful of beginnings, and must accept a shorter text whenever it accepts a longer one.
public func shortened(_ title: String, toFit fits: (String) -> Bool) -> String {
    if fits(title) { return title }
    var low = 0, high = title.count
    while low < high {
        let middle = (low + high + 1) / 2
        if fits(String(title.prefix(middle)) + "…") { low = middle } else { high = middle - 1 }
    }
    return String(title.prefix(low)) + "…"
}

/// What to keep at launch. A clip stays when its data file `<id>.plist` is in `files`, the names
/// found in the clips folder. `strays` are the names that belong to no kept clip, to be deleted.
public func reconcile(index: [Clip], files: Set<String>) -> (clips: [Clip], strays: [String]) {
    let clips = index.filter { files.contains($0.id + ".plist") }
    let owned = Set(clips.flatMap { [$0.id + ".plist", $0.id + ".png"] })
    return (clips, files.subtracting(owned).sorted())
}
