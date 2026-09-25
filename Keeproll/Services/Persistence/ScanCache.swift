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

    private let url: URL
    private var features: [String: FeatureRecord] = [:]
    private var sizes: [String: SizeRecord] = [:]
    private var loaded = false
    private var dirty = false

    private static let magic: UInt32 = 0x5346_5443 // "SFTC"
    private static let version: UInt32 = 4 // 2: sharpness at 160 px; 3: iCloud-only flag; 4: contrast-normalised sharpness
    private static let emptyPrint = UInt32.max

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

    func forget(_ ids: some Sequence<String>) {
        loadIfNeeded()
        for id in ids {
            features[id] = nil
            sizes[id] = nil
        }
        dirty = true
    }

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
        loadedFeatures.reserveCapacity(Int(featureCount))
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
        features = loadedFeatures
        sizes = loadedSizes
        Log.scan.debug("Scan cache loaded: \(loadedFeatures.count) features, \(loadedSizes.count) sizes")
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
