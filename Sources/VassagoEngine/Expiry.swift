/// When the Mac's clipboard is emptied: once it has held the same thing for as long as the user allows.
public struct Expiry {
    /// The clipboard's change counter at the last look, and when it was first seen at that value.
    private var count: Int?
    private var since = 0.0

    public init() {}

    /// Asked at every look at the counter. True when the clipboard is to be emptied now.
    /// `after` is in the unit of `time`; nil never empties it.
    public mutating func check(count: Int, at time: Double, after: Double?) -> Bool {
        if count != self.count {
            self.count = count
            since = time
            return false
        }
        guard let after else { return false }
        return time - since >= after
    }

    /// The clipboard was emptied, which moved its counter to `count`. Nothing is due until it moves again.
    public mutating func emptied(count: Int) {
        self.count = count
        since = .infinity
    }
}
