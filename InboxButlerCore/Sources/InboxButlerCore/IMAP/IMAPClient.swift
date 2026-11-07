import Foundation
import Network

/// The raw byte pipe to the mail server. A real TLS connection in the app, a script in tests.
protocol IMAPTransport: Sendable {
    func connect(host: String, port: Int) async throws
    func send(_ data: Data) async throws
    /// The next chunk of bytes from the server. Throws when the connection closes.
    func receive() async throws -> Data
    func close() async
}

/// TLS connection using Apple's Network framework. IMAP over TLS (port 993) only:
/// credentials are never sent in the clear.
final class NWIMAPTransport: IMAPTransport, @unchecked Sendable {
    private var connection: NWConnection?
    private let lock = NSLock()

    private final class Once: @unchecked Sendable {
        private var fired = false
        private let lock = NSLock()
        func run(_ work: () -> Void) {
            lock.lock(); defer { lock.unlock() }
            if !fired { fired = true; work() }
        }
    }

    func connect(host: String, port: Int) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { throw IMAPError.parse("bad port") }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tls)
        lock.lock(); connection = conn; lock.unlock()
        let once = Once()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { continuation.resume() }
                case .failed(let error):
                    once.run { continuation.resume(throwing: error) }
                case .waiting(let error):
                    // No route / no network: fail fast instead of waiting forever.
                    once.run { continuation.resume(throwing: error) }
                    conn.cancel()
                case .cancelled:
                    once.run { continuation.resume(throwing: IMAPError.connectionClosed) }
                default:
                    break
                }
            }
            conn.start(queue: DispatchQueue.global(qos: .userInitiated))
        }
    }

    func send(_ data: Data) async throws {
        guard let conn = current() else { throw IMAPError.connectionClosed }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    func receive() async throws -> Data {
        guard let conn = current() else { throw IMAPError.connectionClosed }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, !data.isEmpty { continuation.resume(returning: data) }
                else if isComplete { continuation.resume(throwing: IMAPError.connectionClosed) }
                else { continuation.resume(returning: Data()) }
            }
        }
    }

    func close() async {
        current()?.cancel()
    }

    private func current() -> NWConnection? {
        lock.lock(); defer { lock.unlock() }
        return connection
    }
}

/// A small, READ-ONLY IMAP client. It opens mailboxes with EXAMINE and fetches with
/// BODY.PEEK, so it can never change flags, move, delete or send anything.
actor IMAPClient {
    private let transport: IMAPTransport
    private var buffer = [UInt8]()
    private var tagCounter = 0

    init(transport: IMAPTransport) { self.transport = transport }

    // MARK: Session

    func connect(host: String, port: Int) async throws {
        try await transport.connect(host: host, port: port)
        let greeting = String(decoding: try await readLine(), as: UTF8.self)
        guard greeting.hasPrefix("* OK") || greeting.hasPrefix("* PREAUTH") else { throw IMAPError.parse("greeting") }
    }

    func login(user: String, password: String) async throws {
        do {
            _ = try await command("LOGIN \(quote(user)) \(quote(password))")
        } catch IMAPError.command {
            throw IMAPError.loginFailed
        }
    }

    func logout() async {
        _ = try? await command("LOGOUT")
        await transport.close()
    }

    func close() async { await transport.close() }

    // MARK: Commands

    func listMailboxes() async throws -> [IMAPMailbox] {
        try await command("LIST \"\" \"*\"").compactMap(IMAPListParser.parse)
    }

    /// Opens a mailbox read-only and returns how many messages it holds.
    func examine(_ mailbox: String) async throws -> Int {
        let lines = try await command("EXAMINE \(quote(mailbox))")
        for raw in lines {
            let text = String(decoding: raw, as: UTF8.self)
            let parts = text.split(separator: " ")
            if parts.count >= 3, parts[0] == "*", parts[2].uppercased() == "EXISTS", let n = Int(parts[1]) { return n }
        }
        return 0
    }

    /// FETCH by message sequence range, e.g. "71:120".
    func fetch(range: String, items: String) async throws -> [IMAPFetch] {
        try await command("FETCH \(range) (\(items))").compactMap(IMAPFetchParser.parse)
    }

    func uidFetch(uid: Int, items: String) async throws -> IMAPFetch? {
        try await command("UID FETCH \(uid) (\(items))").compactMap(IMAPFetchParser.parse).first
    }

    // MARK: Plumbing

    /// Sends a tagged command and returns the untagged responses until the tagged status.
    private func command(_ text: String) async throws -> [Data] {
        tagCounter += 1
        let tag = String(format: "A%03d", tagCounter)
        try await transport.send(Data("\(tag) \(text)\r\n".utf8))
        var untagged: [Data] = []
        while true {
            let response = try await readResponse()
            let line = String(decoding: response.prefix(200), as: UTF8.self)
            if line.hasPrefix(tag + " ") {
                let status = line.dropFirst(tag.count + 1)
                if status.uppercased().hasPrefix("OK") { return untagged }
                throw IMAPError.command(String(status.prefix(120)))
            } else if line.hasPrefix("* ") {
                untagged.append(response)
            }
            // "+ ..." continuation requests are ignored (we never send literals).
        }
    }

    /// One logical response: a line, plus any {n} literals it announces, joined back together.
    private func readResponse() async throws -> Data {
        var raw = try await readLine()
        while let n = literalLength(in: raw) {
            raw.append(contentsOf: [0x0D, 0x0A])
            raw.append(contentsOf: try await readExact(n))
            raw.append(contentsOf: try await readLine())
        }
        return Data(raw)
    }

    /// If the line ends with `{123}`, the number of literal bytes that follow.
    private func literalLength(in line: [UInt8]) -> Int? {
        guard line.last == UInt8(ascii: "}"), let open = line.lastIndex(of: UInt8(ascii: "{")) else { return nil }
        let digits = line[(open + 1)..<(line.count - 1)]
        guard !digits.isEmpty, digits.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        return Int(String(decoding: digits, as: UTF8.self))
    }

    private func readLine() async throws -> [UInt8] {
        while true {
            if let i = indexOfCRLF() {
                let line = Array(buffer[0..<i])
                buffer.removeSubrange(0..<(i + 2))
                return line
            }
            try await fill()
        }
    }

    private func readExact(_ n: Int) async throws -> [UInt8] {
        while buffer.count < n { try await fill() }
        let out = Array(buffer[0..<n])
        buffer.removeSubrange(0..<n)
        return out
    }

    private func fill() async throws {
        let chunk = try await transport.receive()
        buffer.append(contentsOf: chunk)
    }

    private func indexOfCRLF() -> Int? {
        guard buffer.count >= 2 else { return nil }
        for i in 0..<(buffer.count - 1) where buffer[i] == 0x0D && buffer[i + 1] == 0x0A { return i }
        return nil
    }

    private func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
