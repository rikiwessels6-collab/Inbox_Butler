import Foundation

/// A parsed IMAP value: an atom, a string/literal, NIL, or a parenthesised list.
indirect enum IMAPValue: Equatable, Sendable {
    case atom(String)
    case string(Data)
    case null
    case list([IMAPValue])

    var data: Data? {
        switch self {
        case .atom(let a): return Data(a.utf8)
        case .string(let d): return d
        default: return nil
        }
    }
    /// Text of an atom or string (UTF-8, lossy). Header text is decoded separately.
    var text: String? { data.map { String(decoding: $0, as: UTF8.self) } }
    var intValue: Int? { if case .atom(let a) = self { return Int(a) } else { return nil } }
    var items: [IMAPValue]? { if case .list(let l) = self { return l } else { return nil } }
    var isNull: Bool { if case .null = self { return true } else { return false } }
}

enum IMAPError: Error, LocalizedError, Sendable {
    case parse(String)
    case connectionClosed
    case command(String)      // server said NO / BAD
    case loginFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .parse(let m): return "Unexpected reply from the mail server (\(m))."
        case .connectionClosed: return "The mail server closed the connection."
        case .command(let m): return "The mail server refused a request: \(m)"
        case .loginFailed: return "The mail server rejected the email address or password."
        case .timeout: return "The mail server took too long to answer."
        }
    }
}

/// Reads one IMAP response (already assembled with its literals) into values.
struct IMAPParser {
    private let bytes: [UInt8]
    private(set) var pos = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    var atEnd: Bool { pos >= bytes.count }

    mutating func skipSpaces() { while pos < bytes.count, bytes[pos] == 0x20 { pos += 1 } }

    mutating func parseValue() throws -> IMAPValue {
        skipSpaces()
        guard pos < bytes.count else { throw IMAPError.parse("unexpected end") }
        switch bytes[pos] {
        case UInt8(ascii: "("):
            pos += 1
            var items: [IMAPValue] = []
            while true {
                skipSpaces()
                guard pos < bytes.count else { throw IMAPError.parse("unterminated list") }
                if bytes[pos] == UInt8(ascii: ")") { pos += 1; break }
                items.append(try parseValue())
            }
            return .list(items)
        case UInt8(ascii: "\""):
            pos += 1
            var out = [UInt8]()
            while pos < bytes.count, bytes[pos] != UInt8(ascii: "\"") {
                if bytes[pos] == UInt8(ascii: "\\"), pos + 1 < bytes.count { pos += 1 }
                out.append(bytes[pos]); pos += 1
            }
            guard pos < bytes.count else { throw IMAPError.parse("unterminated string") }
            pos += 1
            return .string(Data(out))
        case UInt8(ascii: "{"):
            pos += 1
            var n = 0
            while pos < bytes.count, bytes[pos] >= 0x30, bytes[pos] <= 0x39 { n = n * 10 + Int(bytes[pos] - 0x30); pos += 1 }
            guard pos < bytes.count, bytes[pos] == UInt8(ascii: "}") else { throw IMAPError.parse("bad literal") }
            pos += 1
            if pos + 1 < bytes.count, bytes[pos] == 0x0D, bytes[pos + 1] == 0x0A { pos += 2 }
            guard pos + n <= bytes.count else { throw IMAPError.parse("short literal") }
            let data = Data(bytes[pos..<(pos + n)])
            pos += n
            return .string(data)
        default:
            // An atom. Square brackets can contain spaces: BODY[HEADER.FIELDS (LIST-ID)].
            var out = [UInt8]()
            var depth = 0
            while pos < bytes.count {
                let c = bytes[pos]
                if c == UInt8(ascii: "[") { depth += 1 }
                else if c == UInt8(ascii: "]") { depth = max(0, depth - 1) }
                else if depth == 0, c == 0x20 || c == UInt8(ascii: "(") || c == UInt8(ascii: ")") { break }
                out.append(c); pos += 1
            }
            let atom = String(decoding: out, as: UTF8.self)
            return atom.uppercased() == "NIL" ? .null : .atom(atom)
        }
    }
}

// MARK: - FETCH data

struct IMAPEnvelope: Sendable {
    var date: String?
    var subject: String?
    var from: [MailAddress]
    var to: [MailAddress]
    var messageID: String?
}

struct IMAPBodyPart: Sendable, Equatable {
    var number: String                 // "1", "2.1", ...
    var type: String                   // lowercased
    var subtype: String
    var params: [String: String]
    var disposition: String?
    var dispositionParams: [String: String]
    var size: Int
    var encoding: String

    var filename: String? {
        MIMEText.parameter(dispositionParams, "filename") ?? MIMEText.parameter(params, "name")
    }
    /// A real attachment (not the message text, not an inline picture in an HTML email).
    var isAttachment: Bool {
        if disposition == "attachment" { return true }
        if disposition == "inline" { return false }
        if type == "text", subtype == "plain" || subtype == "html" { return false }
        return filename != nil
    }
    var charset: String? { params["charset"] }
}

struct IMAPFetch: Sendable {
    var sequence = 0
    var uid: Int?
    var flags: [String] = []
    var internalDate: Date?
    var envelope: IMAPEnvelope?
    var parts: [IMAPBodyPart] = []
    var sections: [String: Data] = [:]     // "BODY[1]<0>" -> bytes

    var isRead: Bool { flags.contains { $0.lowercased() == "\\seen" } }

    func section(prefix: String) -> Data? {
        sections.first { $0.key.hasPrefix(prefix.uppercased()) }?.value
    }
}

enum IMAPFetchParser {
    /// Parses `* 12 FETCH (UID 345 FLAGS (\Seen) ...)`.
    static func parse(_ raw: Data) -> IMAPFetch? {
        var parser = IMAPParser(raw)
        guard let star = try? parser.parseValue(), star == .atom("*"),
              let seq = try? parser.parseValue(), let n = seq.intValue,
              let word = try? parser.parseValue(), word.text?.uppercased() == "FETCH",
              let list = try? parser.parseValue(), let items = list.items else { return nil }

        var fetch = IMAPFetch(sequence: n)
        var i = 0
        while i + 1 < items.count {
            guard let name = items[i].text?.uppercased() else { i += 1; continue }
            let value = items[i + 1]
            switch name {
            case "UID": fetch.uid = value.intValue
            case "FLAGS": fetch.flags = (value.items ?? []).compactMap(\.text)
            case "INTERNALDATE": fetch.internalDate = value.text.flatMap(parseInternalDate)
            case "ENVELOPE": fetch.envelope = parseEnvelope(value)
            case "BODYSTRUCTURE", "BODY":
                if name == "BODYSTRUCTURE" || value.items != nil { fetch.parts = parseStructure(value) }
            default:
                if name.hasPrefix("BODY["), let d = value.data { fetch.sections[name] = d }
            }
            i += 2
        }
        return fetch
    }

    static func parseInternalDate(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MMM-yyyy HH:mm:ss Z"
        return f.date(from: text.trimmingCharacters(in: .whitespaces))
    }

    // MARK: Envelope

    static func parseEnvelope(_ value: IMAPValue) -> IMAPEnvelope? {
        guard let f = value.items, f.count >= 10 else { return nil }
        func header(_ v: IMAPValue) -> String? { v.data.map { MIMEText.decodeEncodedWords(String(decoding: $0, as: UTF8.self)) } }
        return IMAPEnvelope(date: v(f[0]), subject: header(f[1]), from: addresses(f[2]), to: addresses(f[5]),
                            messageID: v(f[9]))
    }

    private static func v(_ value: IMAPValue) -> String? { value.text }

    private static func addresses(_ value: IMAPValue) -> [MailAddress] {
        (value.items ?? []).compactMap { entry in
            guard let a = entry.items, a.count >= 4, let mailbox = a[2].text, let host = a[3].text else { return nil }
            let name = a[0].data.map { MIMEText.decodeEncodedWords(String(decoding: $0, as: UTF8.self)) }
            return MailAddress(name: (name?.isEmpty == false) ? name : nil, address: "\(mailbox)@\(host)")
        }
    }

    // MARK: Body structure

    /// Flattens the MIME tree into its leaf parts, numbered the way IMAP addresses them.
    static func parseStructure(_ value: IMAPValue) -> [IMAPBodyPart] {
        var parts: [IMAPBodyPart] = []
        walk(value, number: "", into: &parts)
        return parts
    }

    private static func walk(_ value: IMAPValue, number: String, into parts: inout [IMAPBodyPart]) {
        guard let items = value.items, !items.isEmpty else { return }
        if case .list = items[0] {
            // Multipart: the leading lists are the children.
            var index = 1
            var i = 0
            while i < items.count, case .list = items[i] {
                walk(items[i], number: number.isEmpty ? "\(index)" : "\(number).\(index)", into: &parts)
                index += 1; i += 1
            }
            return
        }
        guard items.count >= 7, let type = items[0].text?.lowercased(), let subtype = items[1].text?.lowercased() else { return }
        let size = items[6].intValue ?? 0
        // Extension fields start after the basic fields; text parts have a line count,
        // message/rfc822 parts have an envelope, a body and a line count.
        var base = 7
        if type == "text" { base = 8 } else if type == "message", subtype == "rfc822" { base = 10 }
        var disposition: String?
        var dispositionParams: [String: String] = [:]
        if items.count > base + 1, let d = items[base + 1].items, let name = d.first?.text {
            disposition = name.lowercased()
            if d.count > 1 { dispositionParams = paramDictionary(d[1]) }
        }
        parts.append(IMAPBodyPart(number: number.isEmpty ? "1" : number, type: type, subtype: subtype,
                                  params: paramDictionary(items[2]), disposition: disposition,
                                  dispositionParams: dispositionParams, size: size,
                                  encoding: items[5].text?.lowercased() ?? "7bit"))
    }

    private static func paramDictionary(_ value: IMAPValue) -> [String: String] {
        guard let l = value.items else { return [:] }
        var out: [String: String] = [:]
        var i = 0
        while i + 1 < l.count {
            if let k = l[i].text?.lowercased(), let val = l[i + 1].text { out[k] = val }
            i += 2
        }
        return out
    }
}

// MARK: - LIST

struct IMAPMailbox: Sendable, Equatable {
    var name: String
    var flags: [String]
    var isSent: Bool { flags.contains { $0.lowercased() == "\\sent" } }
}

enum IMAPListParser {
    /// Parses `* LIST (\HasNoChildren \Sent) "/" "Sent Messages"`.
    static func parse(_ raw: Data) -> IMAPMailbox? {
        var parser = IMAPParser(raw)
        guard let star = try? parser.parseValue(), star == .atom("*"),
              let word = try? parser.parseValue(), word.text?.uppercased() == "LIST",
              let flags = try? parser.parseValue(), let items = flags.items,
              (try? parser.parseValue()) != nil,
              let name = try? parser.parseValue(), let text = name.text else { return nil }
        return IMAPMailbox(name: text, flags: items.compactMap(\.text))
    }
}
