import Foundation

/// One CSV record, as RFC 4180 describes: fields joined by commas, a field that holds a comma,
/// a double quote or a line break put in double quotes with its own quotes doubled, then CRLF.
public func csvLine(_ fields: [String]) -> String {
    let special = CharacterSet(charactersIn: ",\"\r\n")
    return fields.map { $0.rangeOfCharacter(from: special) == nil ? $0 : "\"" + $0.replacing("\"", with: "\"\"") + "\"" }
        .joined(separator: ",") + "\r\n"
}
