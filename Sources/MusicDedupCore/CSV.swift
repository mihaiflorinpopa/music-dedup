import Foundation

/// One CSV record, as RFC 4180 describes: fields joined by commas, a field that holds a comma,
/// a double quote or a line break put in double quotes with its own quotes doubled, then CRLF.
///
/// A field starting with a character OWASP's CSV Injection page lists (= + - @, tab, a line break,
/// or the full-width ＝ ＋ － ＠) gets an apostrophe first, as that page advises, so a spreadsheet
/// app shows it as text instead of running it as a formula. Excel shows the apostrophe.
public func csvLine(_ fields: [String]) -> String {
    let special = CharacterSet(charactersIn: ",\"\r\n")
    let formula: Set<Character> = ["=", "+", "-", "@", "\t", "\r", "\n", "\r\n", "＝", "＋", "－", "＠"]
    return fields.map { field in
        let text = field.first.map(formula.contains) == true ? "'" + field : field
        return text.rangeOfCharacter(from: special) == nil ? text : "\"" + text.replacing("\"", with: "\"\"") + "\""
    }
    .joined(separator: ",") + "\r\n"
}
