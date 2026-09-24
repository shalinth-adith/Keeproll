import Foundation
import Testing
@testable import Sift

struct ContactDeduplicatorTests {
    private func contact(_ id: String, _ given: String, _ family: String = "",
                         phones: [String] = [], emails: [String] = []) -> ContactSummary {
        ContactSummary(id: id, givenName: given, familyName: family, organization: "", phones: phones, emails: emails, hasImage: false)
    }

    @Test func phoneFormatsNormaliseToTheSameKey() {
        let keys = ["+91 98400 12345", "098400-12345", "(984) 001-2345", "9840012345"].map(ContactNormalizer.phoneKey)
        #expect(Set(keys).count == 1)
        #expect(ContactNormalizer.phoneKey("12345") == nil) // too short
    }

    @Test func nameKeyIgnoresOrderCaseAndAccents() {
        #expect(ContactNormalizer.nameKey(given: "Kavya", family: "Nair") == ContactNormalizer.nameKey(given: "NAIR", family: "kávya"))
        #expect(ContactNormalizer.nameKey(given: "Mom", family: "") == nil) // single token is too weak
    }

    @Test func groupsBySharedPhoneEmailOrName() {
        let groups = ContactDeduplicator.groups([
            contact("1", "Priya", "Raman", phones: ["+91 98400 12345"]),
            contact("2", "Priya", phones: ["98400 12345"]),
            contact("3", "Arun", "Sekar", emails: ["Arun@Example.test"]),
            contact("4", "Arun", "S", emails: ["arun@example.test "]),
            contact("5", "Kavya", "Nair"),
            contact("6", "Nair", "Kavya"),
            contact("7", "Unrelated", "Person", phones: ["+91 90000 00000"]),
        ])
        let byMembers = Dictionary(uniqueKeysWithValues: groups.map { (Set($0.contacts.map(\.id)), $0.reasons) })
        #expect(byMembers.count == 3)
        #expect(byMembers[["1", "2"]] == [.samePhone])
        #expect(byMembers[["3", "4"]] == [.sameEmail])
        #expect(byMembers[["5", "6"]] == [.sameName])
    }

    @Test func transitiveMatchesJoinOneGroup() {
        // 1–2 share a phone, 2–3 share an email: all three are the same person.
        let groups = ContactDeduplicator.groups([
            contact("1", "A", "B", phones: ["9840012345"]),
            contact("2", "C", "D", phones: ["9840012345"], emails: ["x@example.test"]),
            contact("3", "E", "F", emails: ["x@example.test"]),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].contacts.count == 3)
        #expect(groups[0].reasons == [.samePhone, .sameEmail])
    }

    @Test func vCardEscapesAndIncludesFields() {
        var card = VCardWriter.Card()
        card.givenName = "Priya"
        card.familyName = "Raman"
        card.organization = "Meridian, Labs; India"
        card.phones = [("_$!<Mobile>!$_", "+91 98400 12345")]
        card.emails = [("", "priya@example.test")]
        let text = VCardWriter.card(card)
        #expect(text.hasPrefix("BEGIN:VCARD\r\nVERSION:3.0\r\n"))
        #expect(text.contains("N:Raman;Priya;;;\r\n"))
        #expect(text.contains("FN:Priya Raman\r\n"))
        #expect(text.contains(#"ORG:Meridian\, Labs\; India"# + "\r\n"))
        #expect(text.contains("TEL;TYPE=MOBILE:+91 98400 12345\r\n"))
        #expect(text.contains("EMAIL;TYPE=INTERNET,OTHER:priya@example.test\r\n"))
        #expect(text.hasSuffix("END:VCARD\r\n"))
    }
}
