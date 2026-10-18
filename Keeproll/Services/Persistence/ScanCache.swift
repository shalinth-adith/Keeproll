import Foundation

/// On-device cache of per-asset scan results, so a rescan only analyses new or edited
/// photos (D13, amended). A record is valid only while the asset's modification date
/// is unchanged.
///
/// Stored as one flat binary file in Application Support. The cache is a pure
/// key-value lookup, so a simple format loads ~10k records (with feature prints) in
/// milliseconds and avoids SwiftData's actor-isolation friction under Swift 6.
actor ScanCache {
    nonisolated struct FeatureRecord: Sendable, Equatable {
        let modified: Double
        let dHash: UInt64
        let sharpness: Float
        let print: [Float]?
    }

    nonisolated struct SizeRecord: Sendable, Equatable {
        let modified: Double
        let bytes: Int64
        /// The original is on this iPhone (false = iCloud only).
        let isLocal: Bool
    }

    /// Where an image came from (bonus: smart categories). Tri-state flags: nil = unknown.
    nonisolated struct ProvenanceRecord: Sendable, Equatable {
        let modified: Double
        let hasCameraMetadata: Bool?
        let isUtility: Bool?
    }

    /// OCR-derived expiry for a screenshot (bonus: smart categories). `kind` nil = looked, found nothing.
    nonisolated struct ExpiryRecord: Sendable, Equatable {
        let modified: Double
        let kind: ExpiryVerdict.Kind?
        let expiresAt: Double
        let mentionedDate: Double
        let confidence: Float
    }

    /// Brightness statistics for Accidental Shots (bonus). Added after v5 as a trailing
    /// section, so older cache files still load (the section is simply absent).
    nonisolated struct ExposureRecord: Sendable, Equatable {
        let modified: Double
        let stats: ExposureStats
    }

    /// Dead stretches found in a video, in seconds, for Smart Trim (bonus). An empty
    /// list means "analysed, nothing to trim". Trailing section, like exposure.
    nonisolated struct TrimRecord: Sendable, Equatable {
        let modified: Double
        let deadRanges: [TrimRange]
        /// Compressed bytes inside the dead ranges; -1 = not measured.
        let deadBytes: Int64
    }

    private let url: URL
    private var exposures: [String: ExposureRecord] = [:]
    private var trims: [String: TrimRecord] = [:]
    private var features: [String: FeatureRecord] = [:]
    private var sizes: [String: SizeRecord] = [:]
    private var provenances: [String: ProvenanceRecord] = [:]
    private var expiries: [String: ExpiryRecord] = [:]
    private var loaded = false
    private var dirty = false

    private static let magic: UInt32 = 0x5346_5443 // "SFTC"
    private static let version: UInt32 = 5 // 2: sharpness at 160 px; 3: iCloud-only flag; 4: contrast-normalised sharpness; 5: provenance + expiry
    private static let emptyPrint = UInt32.max
    /// Bump when the Accidental Shots statistics change meaning; stale ones are dropped.
    /// 3 adds lit share and saturation, a soft-edge finger score, and a byte length per
    /// section so a stale section is skipped cleanly.
    private static let exposureVersion: UInt8 = 3
    /// Bump when the Smart Trim rules change; stale dead ranges are dropped.
    /// 4: dead means dark and quiet (sound is checked); section length prefix.
    private static let trimVersion: UInt8 = 4

    init(url: URL = ScanCache.defaultURL) {
        self.url = url
    }

    nonisolated static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ScanCache.bin")
    }

    var featureCount: Int { loadIfNeeded(); return features.count }

    func feature(for id: String, modified: Date?) -> FeatureRecord? {
        loadIfNeeded()
        guard let record = features[id], record.modified == Self.stamp(modified) else { return nil }
        return record
    }

    func store(_ record: FeatureRecord, for id: String) {
        loadIfNeeded()
        features[id] = record
        dirty = true
    }

    func storage(for id: String, modified: Date?) -> AssetStorageInfo? {
        loadIfNeeded()
        guard let record = sizes[id], record.modified == Self.stamp(modified) else { return nil }
        return AssetStorageInfo(bytes: record.bytes, isLocal: record.isLocal)
    }

    func store(_ info: AssetStorageInfo, for id: String, modified: Date?) {
        loadIfNeeded()
        sizes[id] = SizeRecord(modified: Self.stamp(modified), bytes: info.bytes, isLocal: info.isLocal)
        dirty = true
    }

    func provenance(for id: String, modified: Date?) -> ProvenanceRecord? {
        loadIfNeeded()
        guard let record = provenances[id], record.modified == Self.stamp(modified) else { return nil }
        return record
    }

    func store(_ record: ProvenanceRecord, for id: String) {
        loadIfNeeded()
        provenances[id] = record
        dirty = true
    }

    func expiry(for id: String, modified: Date?) -> ExpiryRecord? {
        loadIfNeeded()
        guard let record = expiries[id], record.modified == Self.stamp(modified) else { return nil }
        return record
    }

    func store(_ record: ExpiryRecord, for id: String) {
        loadIfNeeded()
        expiries[id] = record
        dirty = true
    }

    func exposure(for id: String, modified: Date?) -> ExposureStats? {
        loadIfNeeded()
        guard let record = exposures[id], record.modified == Self.stamp(modified) else { return nil }
        return record.stats
    }

    func store(_ stats: ExposureStats, for id: String, modified: Date?) {
        loadIfNeeded()
        exposures[id] = ExposureRecord(modified: Self.stamp(modified), stats: stats)
        dirty = true
    }

    func trim(for id: String, modified: Date?) -> (ranges: [TrimRange], deadBytes: Int64?)? {
        loadIfNeeded()
        guard let record = trims[id], record.modified == Self.stamp(modified) else { return nil }
        return (record.deadRanges, record.deadBytes >= 0 ? record.deadBytes : nil)
    }

    func store(trim ranges: [TrimRange], deadBytes: Int64? = nil, for id: String, modified: Date?) {
        loadIfNeeded()
        trims[id] = TrimRecord(modified: Self.stamp(modified), deadRanges: ranges, deadBytes: deadBytes ?? -1)
        dirty = true
    }

    func forget(_ ids: some Sequence<String>) {
        loadIfNeeded()
        for id in ids {
            exposures[id] = nil
            trims[id] = nil
            features[id] = nil
            sizes[id] = nil
            provenances[id] = nil
            expiries[id] = nil
        }
        dirty = true
    }

    /// Tri-state flag encoding: 0 unknown, 1 false, 2 true.
    private static func byte(_ flag: Bool?) -> UInt8 { flag.map { $0 ? 2 : 1 } ?? 0 }
    private static func flag(_ byte: UInt8) -> Bool? { byte == 0 ? nil : byte == 2 }
    private static let kinds = ExpiryVerdict.Kind.allCases

    /// Writes the cache if anything changed. Atomic, so a crash mid-write can't corrupt it.
    func save() {
        guard dirty else { return }
        var writer = BinaryWriter()
        writer.append(Self.magic)
        writer.append(Self.version)
        writer.append(UInt32(features.count))
        for (id, record) in features {
            writer.append(id)
            writer.append(record.modified)
            writer.append(record.dHash)
            writer.append(record.sharpness)
            // 0 = no print wanted, emptyPrint = Vision tried and failed, n = n floats.
            switch record.print {
            case nil: writer.append(UInt32(0))
            case let print? where print.isEmpty: writer.append(Self.emptyPrint)
            case let print?:
                writer.append(UInt32(print.count))
                writer.append(print)
            }
        }
        writer.append(UInt32(sizes.count))
        for (id, record) in sizes {
            writer.append(id)
            writer.append(record.modified)
            writer.append(record.bytes)
            writer.append(UInt8(record.isLocal ? 1 : 0))
        }
        writer.append(UInt32(provenances.count))
        for (id, record) in provenances {
            writer.append(id)
            writer.append(record.modified)
            writer.append(Self.byte(record.hasCameraMetadata))
            writer.append(Self.byte(record.isUtility))
        }
        writer.append(UInt32(expiries.count))
        for (id, record) in expiries {
            writer.append(id)
            writer.append(record.modified)
            writer.append(UInt8(record.kind.flatMap { Self.kinds.firstIndex(of: $0) }.map { $0 + 1 } ?? 0))
            writer.append(record.expiresAt)
            writer.append(record.mentionedDate)
            writer.append(record.confidence)
        }
        // Trailing sections: count, version, byte length, records. The length lets a
        // reader skip a section whose version it doesn't understand.
        var exposureBlock = BinaryWriter()
        for (id, record) in exposures {
            exposureBlock.append(id)
            exposureBlock.append(record.modified)
            exposureBlock.append(record.stats.mean)
            exposureBlock.append(record.stats.standardDeviation)
            exposureBlock.append(record.stats.p98)
            exposureBlock.append(record.stats.maximum)
            exposureBlock.append(record.stats.litPerTenThousand)
            exposureBlock.append(record.stats.saturation)
            exposureBlock.append(record.stats.fingerScore)
        }
        writer.append(UInt32(exposures.count))
        writer.append(Self.exposureVersion)
        writer.append(UInt32(exposureBlock.data.count))
        writer.append(raw: exposureBlock.data)
        var trimBlock = BinaryWriter()
        for (id, record) in trims {
            trimBlock.append(id)
            trimBlock.append(record.modified)
            trimBlock.append(record.deadBytes)
            trimBlock.append(UInt16(min(record.deadRanges.count, Int(UInt16.max))))
            for range in record.deadRanges.prefix(Int(UInt16.max)) {
                trimBlock.append(range.start)
                trimBlock.append(range.end)
            }
        }
        writer.append(UInt32(trims.count))
        writer.append(Self.trimVersion)
        writer.append(UInt32(trimBlock.data.count))
        writer.append(raw: trimBlock.data)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writer.data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            dirty = false
            Log.scan.debug("Scan cache saved: \(self.features.count) features, \(self.sizes.count) sizes, \(writer.data.count) bytes")
        } catch {
            Log.scan.error("Scan cache save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: url) else { return }
        var reader = BinaryReader(data: data)
        guard reader.read(UInt32.self) == Self.magic, reader.read(UInt32.self) == Self.version,
              let featureCount = reader.read(UInt32.self) else {
            Log.scan.debug("Scan cache missing or from another version; starting fresh")
            return
        }
        var loadedFeatures: [String: FeatureRecord] = [:]
        // A corrupt count must not reserve gigabytes: each record is at least 28 bytes (QA L8).
        loadedFeatures.reserveCapacity(min(Int(featureCount), reader.remaining / 28))
        for _ in 0..<featureCount {
            guard let id = reader.readString(), let modified = reader.read(Double.self),
                  let hash = reader.read(UInt64.self), let sharpness = reader.read(Float.self),
                  let printCount = reader.read(UInt32.self) else { return }
            var print: [Float]?
            if printCount == Self.emptyPrint {
                print = []
            } else if printCount > 0 {
                guard let values = reader.readFloats(Int(printCount)) else { return }
                print = values
            }
            loadedFeatures[id] = FeatureRecord(modified: modified, dHash: hash, sharpness: sharpness, print: print)
        }
        guard let sizeCount = reader.read(UInt32.self) else { return }
        var loadedSizes: [String: SizeRecord] = [:]
        for _ in 0..<sizeCount {
            guard let id = reader.readString(), let modified = reader.read(Double.self),
                  let bytes = reader.read(Int64.self), let local = reader.read(UInt8.self) else { return }
            loadedSizes[id] = SizeRecord(modified: modified, bytes: bytes, isLocal: local == 1)
        }
        var loadedProvenance: [String: ProvenanceRecord] = [:]
        var loadedExpiry: [String: ExpiryRecord] = [:]
        if let provenanceCount = reader.read(UInt32.self) {
            for _ in 0..<provenanceCount {
                guard let id = reader.readString(), let modified = reader.read(Double.self),
                      let camera = reader.read(UInt8.self), let utility = reader.read(UInt8.self) else { return }
                loadedProvenance[id] = ProvenanceRecord(modified: modified, hasCameraMetadata: Self.flag(camera), isUtility: Self.flag(utility))
            }
        }
        if let expiryCount = reader.read(UInt32.self) {
            for _ in 0..<expiryCount {
                guard let id = reader.readString(), let modified = reader.read(Double.self), let kindByte = reader.read(UInt8.self),
                      let expires = reader.read(Double.self), let mentioned = reader.read(Double.self),
                      let confidence = reader.read(Float.self) else { return }
                // An unknown kind (corruption, or a newer build's kind) is read as "none" (QA L8).
                let kindIndex = Int(kindByte) - 1
                let kind = Self.kinds.indices.contains(kindIndex) ? Self.kinds[kindIndex] : nil
                loadedExpiry[id] = ExpiryRecord(modified: modified, kind: kind, expiresAt: expires, mentionedDate: mentioned, confidence: confidence)
            }
        }
        var loadedExposure: [String: ExposureRecord] = [:]
        var loadedTrims: [String: TrimRecord] = [:]
        // Sections from before the length prefix (exposure v2, trim v3) can't be skipped;
        // stop there and let the next scan recompute them.
        var sectionsReadable = false
        exposureSection: if let exposureCount = reader.read(UInt32.self), let version = reader.read(UInt8.self) {
            guard version >= 3, let length = reader.read(UInt32.self) else { break exposureSection }
            sectionsReadable = true
            guard version == Self.exposureVersion else { reader.skip(Int(length)); break exposureSection }
            let end = reader.offsetValue + Int(length)
            for _ in 0..<exposureCount {
                guard let id = reader.readString(), let modified = reader.read(Double.self),
                      let mean = reader.read(UInt8.self), let deviation = reader.read(UInt8.self),
                      let p98 = reader.read(UInt8.self), let maximum = reader.read(UInt8.self),
                      let lit = reader.read(UInt8.self), let saturation = reader.read(UInt8.self),
                      let finger = reader.read(UInt8.self) else { break }
                loadedExposure[id] = ExposureRecord(modified: modified, stats: ExposureStats(
                    mean: mean, standardDeviation: deviation, p98: p98, maximum: maximum,
                    litPerTenThousand: lit, saturation: saturation, fingerScore: finger))
            }
            reader.seek(to: end)
        }
        if sectionsReadable {
            trimSection: if let trimCount = reader.read(UInt32.self), let trimVersion = reader.read(UInt8.self),
                            let trimLength = reader.read(UInt32.self) {
                guard trimVersion == Self.trimVersion else { reader.skip(Int(trimLength)); break trimSection }
                trimLoop: for _ in 0..<trimCount {
                    guard let id = reader.readString(), let modified = reader.read(Double.self),
                          let deadBytes = reader.read(Int64.self),
                          let rangeCount = reader.read(UInt16.self),
                          Int(rangeCount) <= reader.remaining / 16 else { break }
                    var ranges: [TrimRange] = []
                    for _ in 0..<rangeCount {
                        guard let start = reader.read(Double.self), let end = reader.read(Double.self) else { break trimLoop }
                        ranges.append(TrimRange(start: start, end: end))
                    }
                    loadedTrims[id] = TrimRecord(modified: modified, deadRanges: ranges, deadBytes: deadBytes)
                }
            }
        }
        exposures = loadedExposure
        trims = loadedTrims
        features = loadedFeatures
        sizes = loadedSizes
        provenances = loadedProvenance
        expiries = loadedExpiry
        Log.scan.debug("Scan cache loaded: \(loadedFeatures.count) features, \(loadedSizes.count) sizes, \(loadedProvenance.count) provenance, \(loadedExpiry.count) expiry")
    }

    private static func stamp(_ date: Date?) -> Double { date?.timeIntervalSinceReferenceDate ?? 0 }
}

// MARK: - Binary helpers (little-endian, native layout)

nonisolated struct BinaryWriter {
    private(set) var data = Data()

    mutating func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func append(_ value: Double) { append(value.bitPattern) }
    mutating func append(_ value: Float) { append(value.bitPattern) }

    mutating func append(_ values: [Float]) {
        for value in values { append(value) }
    }

    mutating func append(raw bytes: Data) { data.append(bytes) }

    mutating func append(_ string: String) {
        let bytes = Array(string.utf8)
        append(UInt32(bytes.count))
        data.append(contentsOf: bytes)
    }
}

nonisolated struct BinaryReader {
    let data: Data
    private var offset = 0

    init(data: Data) { self.data = data }

    /// Bytes left to read.
    var remaining: Int { data.count - offset }
    var offsetValue: Int { offset }

    /// Moves forward `count` bytes, never past the end.
    mutating func skip(_ count: Int) { offset = min(data.count, offset + max(0, count)) }

    /// Jumps to `position`, clamped to the data.
    mutating func seek(to position: Int) { offset = min(data.count, max(0, position)) }

    mutating func read<T: FixedWidthInteger>(_: T.Type) -> T? {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else { return nil }
        var value: T = 0
        _ = withUnsafeMutableBytes(of: &value) { buffer in
            data.copyBytes(to: buffer, from: (data.startIndex + offset)..<(data.startIndex + offset + size))
        }
        offset += size
        return T(littleEndian: value)
    }

    mutating func read(_: Double.Type) -> Double? { read(UInt64.self).map(Double.init(bitPattern:)) }
    mutating func read(_: Float.Type) -> Float? { read(UInt32.self).map(Float.init(bitPattern:)) }

    mutating func readFloats(_ count: Int) -> [Float]? {
        // Never trust a length the file can't actually hold (QA L8).
        guard count >= 0, count <= remaining / MemoryLayout<UInt32>.size else { return nil }
        var values: [Float] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            guard let value = read(Float.self) else { return nil }
            values.append(value)
        }
        return values
    }

    mutating func readString() -> String? {
        guard let length = read(UInt32.self), offset + Int(length) <= data.count else { return nil }
        let start = data.startIndex + offset
        let string = String(decoding: data[start..<(start + Int(length))], as: UTF8.self)
        offset += Int(length)
        return string
    }
}
