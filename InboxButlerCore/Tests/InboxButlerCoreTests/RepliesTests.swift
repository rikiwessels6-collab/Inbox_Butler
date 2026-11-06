import XCTest
@testable import InboxButlerCore

final class RepliesTests: XCTestCase {
    private let acc = UUID()
    private let now = Date()
    private let me: Set<String> = ["me@x.com"]

    private func msg(_ id: String, from: String, to: [String] = ["me@x.com"], thread: String, daysAgo: Double,
                     bulk: Bool = false, subject: String = "S") -> MailMessage {
        MailMessage(accountID: acc, providerMessageID: id, threadID: thread,
                    from: MailAddress(name: from.split(separator: "@").first.map(String.init), address: from),
                    to: to.map { MailAddress(address: $0) }, subject: subject, snippet: "",
                    receivedAt: now.addingTimeInterval(-daysAgo * 86_400), isBulk: bulk)
    }

    func testAwaitingMyReplyIgnoresAnsweredBulkAndOldMail() {
        let waiting = msg("a", from: "sam@work.com", thread: "t1", daysAgo: 1)
        let answeredIn = msg("b", from: "kim@work.com", thread: "t2", daysAgo: 2)
        let answeredOut = msg("b2", from: "me@x.com", to: ["kim@work.com"], thread: "t2", daysAgo: 1)
        let news = msg("c", from: "news@shop.com", thread: "t3", daysAgo: 1, bulk: true)
        let noreply = msg("d", from: "no-reply@bank.com", thread: "t4", daysAgo: 1)
        let old = msg("e", from: "old@work.com", thread: "t5", daysAgo: 40)
        let status = ReplyTracker.analyze(inbox: [waiting, answeredIn, news, noreply, old],
                                          sent: [answeredOut], myAddresses: me, now: now)
        XCTAssertEqual(status.awaitingMyReply, [waiting.id])
    }

    func testFollowUpNeedsQuietPeriodAndNoAnswer() {
        let quiet = msg("s1", from: "me@x.com", to: ["sam@work.com"], thread: "t1", daysAgo: 5)
        let recent = msg("s2", from: "me@x.com", to: ["kim@work.com"], thread: "t2", daysAgo: 1)
        let answeredSent = msg("s3", from: "me@x.com", to: ["lee@work.com"], thread: "t3", daysAgo: 6)
        let answer = msg("r3", from: "lee@work.com", thread: "t3", daysAgo: 4)
        let toBot = msg("s4", from: "me@x.com", to: ["no-reply@bank.com"], thread: "t4", daysAgo: 6)
        let status = ReplyTracker.analyze(inbox: [answer], sent: [quiet, recent, answeredSent, toBot], myAddresses: me, now: now)
        XCTAssertEqual(status.awaitingTheirReply.map(\.id), [quiet.id])
    }

    func testFollowUpNotificationsOnlyForPrioritySenders() {
        let acct = MailAccount(id: acc, kind: .gmail, emailAddress: "me@x.com", label: "Work", colorIndex: 0)
        let toVIP = msg("s1", from: "me@x.com", to: ["sam@work.com"], thread: "t1", daysAgo: 5, subject: "Contract")
        let toOther = msg("s2", from: "me@x.com", to: ["bob@else.com"], thread: "t2", daysAgo: 5)
        let prio = [PrioritySender(input: "sam@work.com")!]
        let plan = FollowUpPlanner.plan(awaiting: [toVIP, toOther], accounts: [acct], priority: prio, alreadyNotified: [])
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].title, "No reply yet from sam")
        XCTAssertEqual(plan[0].body, "Contract")
        XCTAssertTrue(FollowUpPlanner.plan(awaiting: [toVIP], accounts: [acct], priority: prio,
                                           alreadyNotified: [FollowUpPlanner.idPrefix + toVIP.id]).isEmpty)
    }

    func testSuggestionsFavourFrequentFastRepliesAndSkipExisting() {
        // Sam wrote, I replied 30 min later, twice; Kim only once; Bob is already priority.
        let in1 = msg("i1", from: "sam@work.com", thread: "a", daysAgo: 3)
        let out1 = MailMessage(accountID: acc, providerMessageID: "o1", threadID: "a", from: MailAddress(address: "me@x.com"),
                               to: [MailAddress(name: "Sam", address: "sam@work.com")], subject: "", snippet: "",
                               receivedAt: in1.receivedAt.addingTimeInterval(1800))
        let in2 = msg("i2", from: "sam@work.com", thread: "b", daysAgo: 2)
        let out2 = MailMessage(accountID: acc, providerMessageID: "o2", threadID: "b", from: MailAddress(address: "me@x.com"),
                               to: [MailAddress(address: "sam@work.com")], subject: "", snippet: "",
                               receivedAt: in2.receivedAt.addingTimeInterval(1800))
        let kim = msg("o3", from: "me@x.com", to: ["kim@work.com"], thread: "c", daysAgo: 2)
        let bob1 = msg("o4", from: "me@x.com", to: ["bob@work.com"], thread: "d", daysAgo: 2)
        let bob2 = msg("o5", from: "me@x.com", to: ["bob@work.com"], thread: "e", daysAgo: 1)
        let s = SuggestedSenders.suggest(sent: [out1, out2, kim, bob1, bob2], inbox: [in1, in2],
                                         existing: [PrioritySender(input: "bob@work.com")!], myAddresses: me)
        XCTAssertEqual(s.map(\.address), ["sam@work.com"])
        XCTAssertEqual(s[0].name, "Sam")
        XCTAssertEqual(s[0].medianReplyMinutes, 30)
        XCTAssertTrue(s[0].reason.contains("30 min"))
    }

    func testBulkDetection() {
        XCTAssertTrue(BulkMailDetector.isBulk(fromAddress: "a@b.com", hasListUnsubscribe: true, hasListID: false, precedence: nil))
        XCTAssertTrue(BulkMailDetector.isBulk(fromAddress: "a@b.com", hasListUnsubscribe: false, hasListID: false, precedence: "bulk"))
        XCTAssertTrue(BulkMailDetector.isBulk(fromAddress: "noreply@b.com", hasListUnsubscribe: false, hasListID: false, precedence: nil))
        XCTAssertFalse(BulkMailDetector.isBulk(fromAddress: "sam@b.com", hasListUnsubscribe: false, hasListID: false, precedence: nil))
    }

    func testSyncEngineReturnsSentMail() async {
        let a = MailAccount(kind: .gmail, emailAddress: "a@b.c", label: "A", colorIndex: 0)
        let engine = SyncEngine(providers: [SentMock(account: a)])
        let result = await engine.refresh()
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertEqual(result.sent.count, 1)
    }
}

/// Mock that returns different mail for inbox and sent.
private struct SentMock: MailProvider {
    let account: MailAccount
    func authorize() async throws {}
    func fetchMessages(in mailbox: Mailbox, since cursor: SyncCursor?, limit: Int) async throws -> MailPage {
        MailPage(messages: [MailMessage(accountID: account.id, providerMessageID: mailbox.rawValue,
                                        from: MailAddress(address: "x@y.z"), subject: mailbox.rawValue, snippet: "",
                                        receivedAt: Date())])
    }
    func fetchBody(for message: MailMessage) async throws -> String { "" }
    func fetchAttachment(_ attachment: AttachmentInfo, in message: MailMessage) async throws -> Data { Data() }
}
