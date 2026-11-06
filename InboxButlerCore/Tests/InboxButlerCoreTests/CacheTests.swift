import XCTest
@testable import InboxButlerCore

@MainActor
final class CacheTests: XCTestCase {
    private func msg(_ acc: UUID, _ id: String, minutesAgo: Double, read: Bool = false) -> MailMessage {
        MailMessage(accountID: acc, providerMessageID: id, from: MailAddress(name: "N", address: "n@x.io"),
                    subject: id, snippet: "s", receivedAt: Date(timeIntervalSinceNow: -minutesAgo * 60), isRead: read)
    }

    func testSyncInsertsUpdatesAndRemovesVanishedMail() throws {
        let cache = try MessageCache(inMemory: true)
        let acc = UUID()
        cache.sync(accountID: acc, fetched: [msg(acc, "a", minutesAgo: 1), msg(acc, "b", minutesAgo: 5), msg(acc, "old", minutesAgo: 500)])
        XCTAssertEqual(cache.load().map(\.subject), ["a", "b", "old"])

        // "b" vanished from the server; "a" is now read; "old" is older than the fetch window so it stays.
        cache.sync(accountID: acc, fetched: [msg(acc, "a", minutesAgo: 1, read: true), msg(acc, "c", minutesAgo: 6)])
        let after = cache.load()
        XCTAssertEqual(after.map(\.subject), ["a", "c", "old"])
        XCTAssertTrue(after[0].isRead)
    }

    func testLocalReadSurvivesSyncAndAccountRemoval() throws {
        let cache = try MessageCache(inMemory: true)
        let a = UUID(), b = UUID()
        let m = msg(a, "x", minutesAgo: 1)
        cache.sync(accountID: a, fetched: [m])
        cache.sync(accountID: b, fetched: [msg(b, "y", minutesAgo: 2)])
        cache.markReadLocally(m.id)
        cache.sync(accountID: a, fetched: [m])            // server still says unread
        XCTAssertTrue(cache.load().first { $0.subject == "x" }!.isRead)
        cache.remove(accountID: a)
        XCTAssertEqual(cache.load().map(\.subject), ["y"])
    }
}
