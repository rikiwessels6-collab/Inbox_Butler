import XCTest
@testable import InboxButlerCore

final class CoreTests: XCTestCase {
    private func account(_ n: Int) -> MailAccount {
        MailAccount(kind: .gmail, emailAddress: "a\(n)@example.com", label: "A\(n)", colorIndex: n)
    }
    private func message(_ acc: MailAccount, _ id: String, minutesAgo: Double) -> MailMessage {
        MailMessage(accountID: acc.id, providerMessageID: id,
                    from: MailAddress(address: "x@y.z"), subject: id, snippet: "",
                    receivedAt: Date(timeIntervalSinceNow: -minutesAgo * 60))
    }

    func testSyncMergesAccountsNewestFirst() async {
        let a = account(0), b = account(1)
        let engine = SyncEngine(providers: [
            MockMailProvider(account: a, messages: [message(a, "old", minutesAgo: 60)]),
            MockMailProvider(account: b, messages: [message(b, "new", minutesAgo: 1)])
        ])
        let result = await engine.refresh()
        XCTAssertEqual(result.messages.map(\.subject), ["new", "old"])
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testFailingProviderDoesNotBlockOthers() async {
        let a = account(0), b = account(1)
        let engine = SyncEngine(providers: [
            GmailProvider(account: a),   // stub: throws notImplemented
            MockMailProvider(account: b, messages: [message(b, "ok", minutesAgo: 1)])
        ])
        let result = await engine.refresh()
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertNotNil(result.errors[a.id])
    }

    func testSameProviderIDInTwoAccountsDoesNotCollide() {
        let a = account(0), b = account(1)
        XCTAssertNotEqual(message(a, "1", minutesAgo: 0).id, message(b, "1", minutesAgo: 0).id)
    }

    func testWidgetSnapshotRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = WidgetSnapshotStore(directory: dir)
        let snap = WidgetSnapshot(repliesWaiting: 3, generatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(store.save(snap))
        XCTAssertEqual(store.load(), snap)
    }
}
