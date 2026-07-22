import Foundation

enum NumberFormat {
    /// Menu-bar abbreviation: 999 → "999", 12_345 → "12.3K", 8_400_000 → "8.4M".
    /// One decimal, trailing ".0" trimmed (1_000 → "1K", not "1.0K").
    static func abbreviated(_ n: Int) -> String {
        let (value, suffix): (Double, String) =
            switch n {
            case ..<1_000: (Double(n), "")
            case ..<1_000_000: (Double(n) / 1_000, "K")
            case ..<1_000_000_000: (Double(n) / 1_000_000, "M")
            default: (Double(n) / 1_000_000_000, "B")
            }
        if suffix.isEmpty { return String(n) }
        // Truncate (not round) so 999_999 shows "999.9K", never a premature "1M".
        let truncated = (value * 10).rounded(.down) / 10
        let s = truncated.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(truncated))
            : String(format: "%.1f", truncated)
        return s + suffix
    }

    /// Full total with grouping separators: 8400123 → "8,400,123".
    static func full(_ n: Int) -> String {
        n.formatted(.number.grouping(.automatic))
    }
}
