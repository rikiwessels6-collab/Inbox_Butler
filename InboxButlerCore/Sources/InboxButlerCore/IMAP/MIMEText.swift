import Foundation

/// Decoders for the text encodings found in email: RFC 2047 headers ("=?utf-8?B?...?="),
/// quoted-printable, base64, and character sets.
enum MIMEText {
    // MARK: Character sets

    static func string(from data: Data, charset: String?) -> String {
        let name = (charset ?? "utf-8").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        switch name {
        case "utf-8", "utf8", "us-ascii", "ascii", "":
            return String(decoding: data, as: UTF8.self)   // lossy: copes with a cut-off multibyte character
        case "iso-8859-1", "latin1", "latin-1":
            return String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
        case "windows-1252", "cp1252":
            return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
        default:
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId {
                let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
                if let s = String(data: data, encoding: enc) { return s }
            }
            return String(decoding: data, as: UTF8.self)
        }
    }

    // MARK: RFC 2047 encoded words

    static func decodeEncodedWords(_ input: String) -> String {
        guard input.contains("=?"),
              let regex = try? NSRegularExpression(pattern: #"=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?="#) else { return input }
        let ns = input as NSString
        var result = ""
        var last = 0
        var previousWasWord = false
        for match in regex.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            let gap = ns.substring(with: NSRange(location: last, length: match.range.location - last))
            // Whitespace between two encoded words is not part of the text.
            if !(previousWasWord && gap.allSatisfy(\.isWhitespace)) { result += gap }
            let charset = ns.substring(with: match.range(at: 1))
            let kind = ns.substring(with: match.range(at: 2)).lowercased()
            let payload = ns.substring(with: match.range(at: 3))
            var bytes: Data?
            if kind == "b" {
                bytes = decodeBase64(Data(payload.utf8))
            } else {
                bytes = decodeQ(payload)
            }
            if let bytes { result += string(from: bytes, charset: charset) } else { result += ns.substring(with: match.range) }
            last = match.range.location + match.range.length
            previousWasWord = true
        }
        result += ns.substring(from: last)
        return result
    }

    private static func decodeQ(_ text: String) -> Data {
        var out = [UInt8]()
        let b = Array(text.utf8)
        var i = 0
        while i < b.count {
            if b[i] == UInt8(ascii: "_") { out.append(0x20); i += 1 }
            else if b[i] == UInt8(ascii: "="), i + 2 < b.count,
                    let h = hexValue(b[i + 1]), let l = hexValue(b[i + 2]) {
                out.append(UInt8(h * 16 + l)); i += 3
            } else { out.append(b[i]); i += 1 }
        }
        return Data(out)
    }

    // MARK: Transfer encodings

    static func decodeTransfer(_ data: Data, encoding: String) -> Data {
        switch encoding.lowercased() {
        case "base64": return decodeBase64(data) ?? Data()
        case "quoted-printable": return decodeQuotedPrintable(data)
        default: return data
        }
    }

    /// Tolerant base64: ignores line breaks and drops a cut-off final group.
    static func decodeBase64(_ data: Data) -> Data? {
        let valid = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=".utf8)
        var filtered = data.filter { valid.contains($0) }
        let usable = filtered.count - (filtered.count % 4)
        filtered = filtered.prefix(usable)
        return Data(base64Encoded: filtered)
    }

    static func decodeQuotedPrintable(_ data: Data) -> Data {
        var out = [UInt8]()
        let b = [UInt8](data)
        var i = 0
        while i < b.count {
            if b[i] == UInt8(ascii: "=") {
                if i + 1 < b.count, b[i + 1] == 0x0A { i += 2; continue }                                  // soft break
                if i + 2 < b.count, b[i + 1] == 0x0D, b[i + 2] == 0x0A { i += 3; continue }                // soft break
                if i + 2 < b.count, let h = hexValue(b[i + 1]), let l = hexValue(b[i + 2]) {
                    out.append(UInt8(h * 16 + l)); i += 3; continue
                }
            }
            out.append(b[i]); i += 1
        }
        return Data(out)
    }

    private static func hexValue(_ c: UInt8) -> Int? {
        switch c {
        case 0x30...0x39: return Int(c) - 0x30
        case 0x41...0x46: return Int(c) - 0x41 + 10
        case 0x61...0x66: return Int(c) - 0x61 + 10
        default: return nil
        }
    }

    // MARK: Helpers

    /// "Re: Fwd: Hello" -> "hello". IMAP has no threads, so this groups a conversation.
    static func normalizedSubject(_ subject: String) -> String {
        var t = subject.lowercased().trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            for prefix in ["re:", "fwd:", "fw:", "aw:", "sv:", "antw:"] where t.hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Reads a MIME parameter that may be plain, RFC 2047 encoded, or RFC 2231 (`name*=utf-8''...`).
    static func parameter(_ params: [String: String], _ key: String) -> String? {
        let k = key.lowercased()
        if let v = params[k] { return decodeEncodedWords(v) }
        if let v = params[k + "*"] {
            let parts = v.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3 { return String(parts[2]).removingPercentEncoding ?? String(parts[2]) }
            return v.removingPercentEncoding ?? v
        }
        return nil
    }
}
