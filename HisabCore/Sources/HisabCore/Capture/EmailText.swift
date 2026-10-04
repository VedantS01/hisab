import Foundation

/// The visible text of an alert email, for the extractor.
///
/// Shortcuts' Email trigger hands an automation the message body as a file,
/// and an alert email's body is usually HTML. The extractor reads at most
/// `max_len` (192) tokens, and a stylesheet alone spends them before the
/// amount, so markup has to go before the read. SMS and notification text is
/// never HTML and passes through untouched.
public enum EmailText {
    /// `text` unchanged unless it looks like HTML; otherwise its text with tags,
    /// styles and scripts removed, entities decoded and whitespace collapsed.
    public static func plain(_ text: String) -> String {
        guard text.range(of: #"<(html|head|body|div|table|tr|td|p|br|span|font)\b"#,
                         options: [.regularExpression, .caseInsensitive]) != nil else { return text }
        var s = text
        s = replace(#"(?is)<(style|script|head)\b.*?</\1\s*>"#, in: s, with: " ")
        s = replace(#"(?s)<!--.*?-->"#, in: s, with: " ")
        s = replace(#"<[^>]*>"#, in: s, with: " ")
        s = decodeNumericEntities(s)
        // `&amp;` last, so "&amp;lt;" decodes to the text "&lt;", not to "<".
        for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                                    ("&apos;", "'"), ("&amp;", "&")] {
            s = s.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        return s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func replace(_ pattern: String, in s: String, with template: String) -> String {
        s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

    /// `&#8377;` and `&#x20B9;` (both ₹), and any other numeric reference.
    private static func decodeNumericEntities(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let hex = match.range(at: 1).length > 0
            let digits = ns.substring(with: match.range(at: 2))
            guard let value = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(value) else { continue }
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            out.unicodeScalars.append(scalar)
            last = match.range.location + match.range.length
        }
        return out + ns.substring(from: last)
    }
}
