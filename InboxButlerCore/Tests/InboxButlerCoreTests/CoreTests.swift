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
            // Not signed in (no tokens in the store): throws notAuthorized.
            GmailProvider(account: a, tokens: GoogleTokenManager(accountID: a.id, auth: GoogleAuth(),
                                                                 secrets: InMemorySecretStore())),
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

    func testSnapshotBuilderPicksUrgentUnreadAndCountsReplies() {
        let a = account(0)
        var urgent = message(a, "u", minutesAgo: 1); urgent.importance = 0.9; urgent.awaitingReply = true
        var read = message(a, "r", minutesAgo: 2); read.importance = 0.95; read.isRead = true
        var low = message(a, "l", minutesAgo: 3); low.importance = 0.2
        let snap = WidgetSnapshot.make(messages: [urgent, read, low], accounts: [a])
        XCTAssertEqual(snap.urgentEmails.map(\.subject), ["u"])
        XCTAssertEqual(snap.repliesWaiting, 1)
    }

    func testPrioritySenderValidationAndMatching() {
        XCTAssertNil(PrioritySender(input: "not an email"))
        XCTAssertNil(PrioritySender(input: "@nodot"))
        let one = PrioritySender(input: " Boss@Work.com ")!
        XCTAssertTrue(one.matches("boss@work.com"))
        XCTAssertFalse(one.matches("other@work.com"))
        let domain = PrioritySender(input: "@work.com")!
        XCTAssertTrue(domain.matches("anyone@WORK.com"))
        XCTAssertFalse(domain.matches("a@notwork.com.evil.io"))
    }

    func testOnlyPrioritySendersNotify() {
        let a = account(0)
        var vip = message(a, "vip", minutesAgo: 1); vip.from = MailAddress(name: "Sam", address: "sam@work.com")
        let other = message(a, "other", minutesAgo: 2)
        var seen = message(a, "seen", minutesAgo: 3); seen.from = vip.from
        var read = message(a, "read", minutesAgo: 4); read.from = vip.from; read.isRead = true
        let prio = [PrioritySender(input: "sam@work.com")!]
        let plan = NotificationPlanner.plan(messages: [vip, other, seen, read], accounts: [a],
                                            priority: prio, alreadyNotified: [seen.id])
        XCTAssertEqual(plan.map(\.id), [vip.id])
        XCTAssertEqual(plan.first?.title, "Sam")
        XCTAssertEqual(plan.first?.body, "vip")
        XCTAssertTrue(NotificationPlanner.plan(messages: [vip], accounts: [a], priority: [], alreadyNotified: []).isEmpty)
    }

    func testPrioritySenderRanksFirstInWidget() {
        let a = account(0)
        var vip = message(a, "vip", minutesAgo: 5); vip.from = MailAddress(address: "sam@work.com")
        var hot = message(a, "hot", minutesAgo: 1); hot.importance = 0.99
        let snap = WidgetSnapshot.make(messages: [hot, vip], accounts: [a],
                                       priority: [PrioritySender(input: "sam@work.com")!])
        XCTAssertEqual(snap.urgentEmails.map(\.subject), ["vip", "hot"])
        XCTAssertEqual(snap.priorityUnreadCount, 1)
    }
}
