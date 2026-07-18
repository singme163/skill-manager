import Foundation

public enum TextLanguage {
    /// True when the text reads as Chinese: at least ~20% CJK ideographs.
    /// Used to decide whether offering a translation makes sense.
    public static func isDominantlyCJK(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return false }
        let cjkCount = scalars.lazy.filter { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))      // CJK Unified
                || (0x3400...0x4DBF).contains(Int(scalar.value)) // Extension A
        }.count
        return cjkCount * 5 >= scalars.count
    }
}
