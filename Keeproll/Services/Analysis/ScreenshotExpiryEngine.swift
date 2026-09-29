import Foundation

/// Reads the text of a screenshot and decides whether what it shows has expired
/// (bonus: smart categories). Pure; unit-tested in `ScreenshotExpiryEngineTests`.
///
/// Kinds and their use-by rules, all measured from the screenshot's capture date
/// unless the text names a later date:
/// - **One-time code** (OTP / verification / 4–8 digit code): 1 day.
/// - **Boarding pass** (gate, seat, boarding, flight number): the travel date, else 2 days.
/// - **Ticket / reservation** (admit, booking, check-in, show): the event date, else 30 days.
/// - **Delivery** (tracking, out for delivery, order shipped): 14 days.
/// - **Coupon / offer** ("valid till", "expires", promo code): the stated date, else 30 days.
/// - **Parking** (parking, bay, level, zone + a time): 1 day.
///
/// Conservative by design: it needs a kind *and* either a past date or an elapsed
/// window; a screenshot with a date that is still in the future is never flagged.
nonisolated enum ScreenshotExpiryEngine {
    struct Rule: Sendable {
        let kind: ExpiryVerdict.Kind
        let keywords: [String]
        let minimumHits: Int
        let window: TimeInterval
        let usesMentionedDate: Bool
    }

    static let day: TimeInterval = 86_400

    static let rules: [Rule] = [
        Rule(kind: .oneTimeCode, keywords: ["otp", "one-time", "one time password", "verification code", "verify code", "your code is",
                                             "security code", "login code", "passcode is", "authentication code", "do not share"],
             minimumHits: 1, window: 1 * day, usesMentionedDate: false),
        Rule(kind: .boardingPass, keywords: ["boarding pass", "boarding", "gate", "seat", "flight", "departure", "pnr", "terminal", "airline"],
             minimumHits: 3, window: 2 * day, usesMentionedDate: true),
        Rule(kind: .parking, keywords: ["parking", "parked", "bay", "level", "zone", "valet", "parking spot", "pillar"],
             minimumHits: 2, window: 1 * day, usesMentionedDate: false),
        Rule(kind: .delivery, keywords: ["tracking", "out for delivery", "shipped", "arriving", "delivery partner", "courier", "awb", "consignment", "on the way"],
             minimumHits: 2, window: 14 * day, usesMentionedDate: false),
        Rule(kind: .coupon, keywords: ["coupon", "promo code", "valid till", "valid until", "valid upto", "expires on", "expires", "offer ends", "use code", "discount code", "voucher"],
             minimumHits: 2, window: 30 * day, usesMentionedDate: true),
        Rule(kind: .reservation, keywords: ["reservation", "booking id", "booking confirmed", "check-in", "check in", "table for", "confirmation number", "appointment"],
             minimumHits: 2, window: 30 * day, usesMentionedDate: true),
        Rule(kind: .ticket, keywords: ["ticket", "admit", "e-ticket", "show time", "screen", "seat no", "row", "entry pass", "event", "venue"],
             minimumHits: 3, window: 30 * day, usesMentionedDate: true),
    ]

    /// Digit runs of 4–8 with spaces or dashes allowed between groups ("482 913", "48-29-13").
    private static let codePattern = try! NSRegularExpression(pattern: #"(?<!\d)(\d[ -]?){3,7}\d(?!\d)"#)

    static func verdict(text: String, capturedOn: Date, now: Date, calendar: Calendar = .current) -> ExpiryVerdict? {
        let lower = text.lowercased()
        guard lower.count >= 12 else { return nil }
        let dates = mentionedDates(in: text, near: capturedOn)

        var best: (ExpiryVerdict, Double)?
        for rule in rules {
            let hits = rule.keywords.filter { lower.contains($0) }.count
            var strength = Double(hits)
            if rule.kind == .oneTimeCode {
                // The code itself counts: "Your code is 482913" needs the digits too.
                let range = NSRange(lower.startIndex..., in: lower)
                guard codePattern.firstMatch(in: lower, range: range) != nil else { continue }
                strength += 1
            }
            guard hits >= rule.minimumHits else { continue }

            let mentioned = rule.usesMentionedDate ? dates.first : nil
            // The moment it stops mattering: the day after the named date, or the window.
            let expiresAt: Date
            if let mentioned {
                expiresAt = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: mentioned)) ?? mentioned.addingTimeInterval(day)
                strength += 1.5
            } else {
                expiresAt = capturedOn.addingTimeInterval(rule.window)
            }
            guard expiresAt < now else { continue } // still useful: never flag

            let confidence = Float(min(1, 0.45 + 0.15 * strength))
            let verdict = ExpiryVerdict(kind: rule.kind, expiresAt: expiresAt, mentionedDate: mentioned, confidence: confidence)
            if best == nil || strength > best!.1 { best = (verdict, strength) }
        }
        return best?.0
    }

    /// Dates the text names, nearest the capture date first. Uses the system data
    /// detector, so "12 Mar", "March 12, 2026", "12/03/26" and "tomorrow" all work.
    static func mentionedDates(in text: String, near reference: Date) -> [Date] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let dates = detector.matches(in: text, range: range).compactMap(\.date)
        // A year-less "12 Mar" is resolved relative to now by the detector; snap it to the
        // capture year when that lands within six months, which is what a screenshot means.
        let calendar = Calendar.current
        let snapped = dates.map { date -> Date in
            guard abs(date.timeIntervalSince(reference)) > 180 * day else { return date }
            var parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
            parts.year = calendar.component(.year, from: reference)
            return calendar.date(from: parts) ?? date
        }
        return snapped.sorted { abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference)) }
    }
}
