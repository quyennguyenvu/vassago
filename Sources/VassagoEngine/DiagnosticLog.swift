/// What the app did and what went wrong since it started: the newest lines, and the text a report is made of.
public struct DiagnosticLog {
    /// A burst of trouble rotates the log; it cannot grow it.
    public static let capacity = 500

    /// Oldest first.
    public private(set) var lines: [String] = []

    public init() {}

    public mutating func note(_ line: String) {
        if lines.count == Self.capacity { lines.removeFirst() }
        lines.append(line)
    }

    /// The header, a blank line, then every line, oldest first.
    public func report(header: [String]) -> String {
        (header + [""] + lines).joined(separator: "\n")
    }

    /// A stored line taken apart for display.
    public struct Parts: Equatable {
        public let date: String
        public let time: String
        public let tag: String
        public let text: String

        public init(date: String, time: String, tag: String, text: String) {
            self.date = date
            self.time = time
            self.tag = tag
            self.text = text
        }

        /// The time for a line written today; the day and the time to the minute for an older one.
        public func stamp(today: String) -> String {
            date == today ? time : "\(date.dropFirst(5)) \(time.prefix(5))"
        }
    }

    /// Splits "2026-11-27 13:26:15.204  [clip] recorded text" into its parts. Nil for any other shape.
    public static func parts(of line: String) -> Parts? {
        let pieces = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard pieces.count == 4, pieces[2].hasPrefix("["), pieces[2].hasSuffix("]") else { return nil }
        return Parts(
            date: String(pieces[0]), time: String(pieces[1]),
            tag: String(pieces[2].dropFirst().dropLast()), text: String(pieces[3]))
    }

    /// For text Vassago did not write, such as another app's bundle id or a clipboard type's name:
    /// a line break in it would forge a line in a report that is meant to be sent. Keeps ASCII
    /// letters and digits, ".", "-" and "_", up to 80 characters.
    public static func clean(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "-", "_": return true
            default: return false
            }
        }
        return String(String.UnicodeScalarView(kept.prefix(80)))
    }
}
