/// A plain three-number version such as 0.2.0. Anything else is refused rather than guessed at.
public struct Version: Comparable {
    private let parts: [Int]

    /// Accepts "0.2.0" or a release tag "v0.2.0".
    public init?(_ text: String) {
        let bare = text.hasPrefix("v") ? text.dropFirst() : text[...]
        let pieces = bare.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = pieces.compactMap { piece -> Int? in
            piece.allSatisfy { ("0"..."9" as ClosedRange<Character>).contains($0) } ? Int(piece) : nil
        }
        guard pieces.count == 3, numbers.count == 3 else { return nil }
        parts = numbers
    }

    public var text: String {
        parts.map(String.init).joined(separator: ".")
    }

    public static func < (a: Version, b: Version) -> Bool {
        a.parts.lexicographicallyPrecedes(b.parts)
    }
}
