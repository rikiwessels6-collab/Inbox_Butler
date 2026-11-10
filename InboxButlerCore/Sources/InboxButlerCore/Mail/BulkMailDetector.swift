import Foundation

/// Spots newsletters and automated mail, so they don't count as "needs a reply"
/// and can be grouped separately.
public enum BulkMailDetector {
    private static let automatedFragments = [
        "noreply", "no-reply", "donotreply", "do-not-reply", "notifications", "notification@",
        "newsletter", "mailer-daemon", "postmaster", "bounce", "automated"
    ]

    /// Addresses that are clearly not a person (no-reply@..., newsletter@...).
    public static func isAutomatedAddress(_ address: String) -> Bool {
        let local = address.lowercased()
        return automatedFragments.contains { local.contains($0) }
    }

    /// `List-Unsubscribe` / `List-Id` headers, or `Precedence: bulk`, mark mailing lists.
    public static func isBulk(fromAddress: String, hasListUnsubscribe: Bool, hasListID: Bool, precedence: String?) -> Bool {
        if hasListUnsubscribe || hasListID { return true }
        if let p = precedence?.lowercased(), ["bulk", "list", "junk"].contains(p) { return true }
        return isAutomatedAddress(fromAddress)
    }

    private static let roleMailboxes = [
        "service", "services", "info", "support", "billing", "statements", "statement", "accounts", "account",
        "alerts", "alert", "orders", "order", "hello", "team", "admin", "office", "enquiries", "contact", "news", "updates"
    ]

    private static let broadcastGreetings = [
        "parents and carers", "students and parents", "parents and students", "dear parents", "dear families",
        "dear carers", "dear students", "dear all", "hi all", "hello all", "hi everyone", "hello everyone",
        "dear community", "dear colleagues", "to all staff", "good afternoon parents", "good morning parents",
        "good afternoon year", "good morning year"
    ]

    /// Mail sent to many people at once, or from a shared mailbox like service@ or info@. Nothing
    /// personal is being asked of you, so it should never count as "needs a reply".
    public static func isBroadcast(fromAddress: String, snippet: String) -> Bool {
        let address = fromAddress.lowercased()
        let local = address.split(separator: "@").first.map(String.init) ?? address
        if roleMailboxes.contains(local) { return true }
        let opening = String(snippet.lowercased().prefix(80))
        return broadcastGreetings.contains { opening.contains($0) }
    }
}
