import Foundation
import Testing
@testable import Keeproll

// MARK: - Saved from chats

struct ProvenanceEngineTests {
    private func provenance(name: String? = "IMG_0042.HEIC", uti: String? = "public.heic", width: Int = 4032, height: Int = 3024,
                            camera: Bool? = true, location: Bool = true, favourite: Bool = false, utility: Bool? = nil) -> AssetProvenance {
        AssetProvenance(originalFilename: name, uniformType: uti, pixelWidth: width, pixelHeight: height,
                        hasCameraMetadata: camera, hasLocation: location, isFavorite: favourite, isUtility: utility)
    }

    @Test func cameraShotIsNeverFlagged() {
        #expect(ProvenanceEngine.verdict(for: provenance()) == nil)
        // Even with every other chat sign present, camera metadata clears it.
        #expect(ProvenanceEngine.verdict(for: provenance(name: "IMG-20240301-WA0007.jpg", uti: "public.jpeg", width: 1600, height: 1200,
                                                          camera: true, location: false, utility: true)) == nil)
    }

    @Test func favouritesAreNeverFlagged() {
        let p = provenance(name: "IMG-20240301-WA0007.jpg", uti: "public.jpeg", width: 1600, height: 1200, camera: false, location: false, favourite: true)
        #expect(ProvenanceEngine.verdict(for: p) == nil)
    }

    @Test func whatsAppForwardIsVeryLikely() {
        let p = provenance(name: "IMG-20240301-WA0007.jpg", uti: "public.jpeg", width: 1600, height: 1200, camera: false, location: false)
        let verdict = ProvenanceEngine.verdict(for: p)
        #expect(verdict?.confidence == .veryLikely)
        #expect(verdict?.source == .whatsapp)
        #expect(verdict?.reasons.contains(.chatFilename) == true)
        #expect(verdict?.reasons.contains(.noCameraData) == true)
    }

    @Test func telegramNamingIsRecognised() {
        let p = provenance(name: "photo_2026-03-12_10-41-07.jpg", uti: "public.jpeg", width: 1280, height: 960, camera: false, location: false)
        #expect(ProvenanceEngine.verdict(for: p)?.source == .telegram)
    }

    @Test func strippedMetadataAtChatSizeIsLikely() {
        // Random iOS-WhatsApp style name, 1600 px long edge, JPEG, no location.
        let p = provenance(name: "UYNZ3K2P.jpg", uti: "public.jpeg", width: 1600, height: 1200, camera: false, location: false)
        let verdict = ProvenanceEngine.verdict(for: p)
        #expect(verdict != nil)
        #expect(verdict!.confidence >= .likely)
        #expect(verdict?.source == .whatsapp) // inferred from the 1600 px edge
    }

    @Test func largeExportWithoutMetadataIsOnlyPossible() {
        // An editing app stripped EXIF but kept 12 MP: probably the user's own photo.
        let p = provenance(name: "Export_0012.jpg", uti: "public.jpeg", width: 4032, height: 3024, camera: false, location: false)
        #expect(ProvenanceEngine.verdict(for: p)?.confidence == .possible)
    }

    @Test func unknownHeaderNeedsAnExplicitChatName() {
        // iCloud-only: header unreadable. Shape and JPEG alone must not flag it.
        #expect(ProvenanceEngine.verdict(for: provenance(name: "IMG_0042.JPG", uti: "public.jpeg", width: 1600, height: 1200, camera: nil, location: false)) == nil)
        #expect(ProvenanceEngine.verdict(for: provenance(name: "IMG-20240301-WA0007.jpg", uti: "public.jpeg", width: 1600, height: 1200, camera: nil, location: false)) != nil)
    }

    @Test func utilityLookRaisesConfidence() {
        let base = provenance(name: "UYNZ3K2P.jpg", uti: "public.jpeg", width: 1080, height: 1080, camera: false, location: false)
        let plain = ProvenanceEngine.verdict(for: base)
        var withUtility = base
        withUtility.isUtility = true
        let boosted = ProvenanceEngine.verdict(for: withUtility)
        #expect(plain != nil && boosted != nil)
        #expect(boosted!.confidence >= plain!.confidence)
        #expect(boosted?.reasons.contains(.utilityLook) == true)
    }

    @Test func missingMetadataAloneIsOnlyPossible() {
        // No camera data, no location, JPEG, but a camera-style name and an odd size: a web save or export.
        let p = provenance(name: "IMG_0042.JPG", uti: "public.jpeg", width: 1500, height: 1000, camera: false, location: false)
        #expect(ProvenanceEngine.verdict(for: p)?.confidence == .possible)
    }

    @Test func cameraFilenamesAreNotChatNames() {
        for name in ["IMG_0042.HEIC", "DSC_1234.JPG", "PXL_20240301_101010.jpg", "IMG_E0042.JPG"] {
            #expect(ProvenanceEngine.classifyFilename(name).1 == 0, "\(name)")
        }
    }
}

// MARK: - Expired screenshots

struct ScreenshotExpiryEngineTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let day: TimeInterval = 86_400

    @Test func oneTimeCodeExpiresAfterADay() {
        let text = "Your verification code is 482913. Do not share it with anyone."
        let fresh = ScreenshotExpiryEngine.verdict(text: text, capturedOn: now.addingTimeInterval(-3600), now: now)
        let old = ScreenshotExpiryEngine.verdict(text: text, capturedOn: now.addingTimeInterval(-3 * day), now: now)
        #expect(fresh == nil)
        #expect(old?.kind == .oneTimeCode)
        #expect(old!.confidence >= ScreenshotExpiryScanner.minimumConfidence)
    }

    @Test func codeKeywordsWithoutDigitsAreNotACode() {
        let text = "Please enter the verification code we sent to your phone."
        #expect(ScreenshotExpiryEngine.verdict(text: text, capturedOn: now.addingTimeInterval(-5 * day), now: now) == nil)
    }

    @Test func boardingPassUsesTheFlightDate() {
        let calendar = Calendar.current
        let flight = calendar.date(byAdding: .day, value: -10, to: now)!
        let dated = flight.formatted(date: .long, time: .omitted)
        let text = "BOARDING PASS\nFlight 6E 2114  Gate 24  Seat 14A\nDeparture \(dated) 06:40\nPNR ZK8Q2L"
        let verdict = ScreenshotExpiryEngine.verdict(text: text, capturedOn: flight.addingTimeInterval(-2 * day), now: now)
        #expect(verdict?.kind == .boardingPass)
        #expect(verdict?.mentionedDate != nil)
        #expect(verdict!.expiresAt < now)
    }

    @Test func futureDatesAreNeverFlagged() {
        let future = now.addingTimeInterval(20 * day).formatted(date: .long, time: .omitted)
        let text = "BOARDING PASS Flight AI 101 Gate 12 Seat 3C Departure \(future)"
        #expect(ScreenshotExpiryEngine.verdict(text: text, capturedOn: now.addingTimeInterval(-40 * day), now: now) == nil)
    }

    @Test func deliveryExpiresAfterTwoWeeks() {
        let text = "Your order is out for delivery. Tracking ID 7788123456 · Delivery partner Ravi"
        #expect(ScreenshotExpiryEngine.verdict(text: text, capturedOn: now.addingTimeInterval(-5 * day), now: now) == nil)
        #expect(ScreenshotExpiryEngine.verdict(text: text, capturedOn: now.addingTimeInterval(-20 * day), now: now)?.kind == .delivery)
    }

    @Test func ordinaryScreenshotsAreLeftAlone() {
        let text = "Hey, are we still on for dinner tonight? 😊\nYes! See you at 8."
        #expect(ScreenshotExpiryEngine.verdict(text: text, capturedOn: now.addingTimeInterval(-400 * day), now: now) == nil)
    }
}

// MARK: - Live Photos

struct LivePhotoCandidateTests {
    @Test func freeableTotalCountsOnlyTheClip() {
        let still = MediaItem(id: "l1", kind: .photo, creationDate: .now, pixelWidth: 3024, pixelHeight: 4032, duration: nil, isFavorite: false, byteSize: 5_000_000)
        let candidate = LivePhotoCandidate(item: still, videoBytes: 3_200_000)
        #expect(candidate.id == "l1")
        #expect(candidate.videoBytes < candidate.item.byteSize ?? 0)
    }

    @Test func convertedOriginalsAreHiddenFromTheList() async throws {
        let defaults = UserDefaults(suiteName: "test.live.\(UUID().uuidString)")!
        let store = ScanStore(permissions: FakePermissions(), storage: FakeStorage(), photos: FakePhotos(screenshots: []), defaults: defaults)
        store.markLivePhotoConverted(original: "orig", still: "new")
        #expect(store.convertedLivePhotos == ["orig", "new"])
    }
}

// MARK: - Storage forecast

struct StorageForecasterTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let total: Int64 = 128_000_000_000

    private func history(days: Int, start: Int64, perDay: Int64) -> [StorageSample] {
        (0..<days).map { i in
            StorageSample(date: now.addingTimeInterval(-Double(days - 1 - i) * 86_400), availableBytes: start + Int64(i) * perDay, totalBytes: total)
        }
    }

    @Test func needsThreeDays() {
        #expect(StorageForecaster.forecast([], now: now) == .notEnoughData(daysRecorded: 0))
        #expect(StorageForecaster.forecast(history(days: 2, start: 20_000_000_000, perDay: -500_000_000), now: now) == .notEnoughData(daysRecorded: 2))
    }

    @Test func fillingPhoneProjectsDaysToTheFloor() {
        // 20 GB free, losing 500 MB a day: (20 - 2) GB / 0.5 GB = 36 days.
        let h = history(days: 10, start: 20_000_000_000 + 9 * 500_000_000, perDay: -500_000_000)
        guard case .filling(let perDay, let days) = StorageForecaster.forecast(h, now: now) else { Issue.record("expected filling"); return }
        #expect(abs(perDay - 500_000_000) < 1_000_000)
        #expect(days == 36)
    }

    @Test func smallDriftIsSteady() {
        #expect(StorageForecaster.forecast(history(days: 7, start: 50_000_000_000, perDay: -5_000_000), now: now) == .steady)
    }

    @Test func growingFreeSpaceIsFreeingUp() {
        guard case .freeingUp(let perDay) = StorageForecaster.forecast(history(days: 7, start: 10_000_000_000, perDay: 300_000_000), now: now) else { Issue.record("expected freeingUp"); return }
        #expect(abs(perDay - 300_000_000) < 1_000_000)
    }

    @Test func oneSamplePerDayLatestWins() {
        let morning = StorageSample(date: now, availableBytes: 10, totalBytes: total)
        let evening = StorageSample(date: now.addingTimeInterval(3600), availableBytes: 20, totalBytes: total)
        let kept = StorageForecaster.appending(evening, to: [morning])
        #expect(kept.count == 1 && kept[0].availableBytes == 20)
    }

    @Test func oldSamplesAreTrimmed() {
        let old = StorageSample(date: now.addingTimeInterval(-60 * 86_400), availableBytes: 1, totalBytes: total)
        let kept = StorageForecaster.appending(StorageSample(date: now, availableBytes: 2, totalBytes: total), to: [old])
        #expect(kept.map(\.availableBytes) == [2])
    }
}
