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
}
