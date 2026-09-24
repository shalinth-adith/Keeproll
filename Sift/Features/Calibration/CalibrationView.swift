import Charts
import Observation
import SwiftUI

#if DEBUG
/// DEBUG-only tool for tuning similarity and blur thresholds on a real library.
/// You label a handful of your own photos; the screen recommends thresholds and can
/// apply them. Labels and ids stay on the device; only numbers go to the console.
@Observable
final class CalibrationViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case similar, blur
        var id: String { rawValue }
    }

    struct Row: Identifiable {
        let threshold: Float
        let precision: Double
        let recall: Double
        let n: Int
        var id: Float { threshold }
    }

    var mode: Mode = .similar
    private(set) var pairLabels: [CalibrationData.Pair: Bool] = [:]
    private(set) var blurLabels: [String: Bool] = [:]
    private let scanStore: ScanStore

    init(scanStore: ScanStore) {
        self.scanStore = scanStore
    }

    var data: CalibrationData? { scanStore.calibration }
    var currentFeatureThreshold: Float { SimilarityConfig.current.featureThreshold }
    var currentBlurThreshold: Float { SimilarityConfig.current.blurThreshold }

    // MARK: Similar pairs

    /// Pairs with feature prints, spread across the distance range, unlabelled first.
    var pairQueue: [CalibrationData.Pair] {
        (data?.samples ?? []).filter { $0.featureDistance != nil && pairLabels[$0] == nil }
            .sorted { ($0.featureDistance ?? 0) < ($1.featureDistance ?? 0) }
    }

    var nextPair: CalibrationData.Pair? {
        // Alternate low and high distances so early answers already span the range.
        let queue = pairQueue
        guard !queue.isEmpty else { return nil }
        return pairLabels.count.isMultiple(of: 2) ? queue[queue.count / 2] : queue[(queue.count / 4)]
    }

    func label(_ pair: CalibrationData.Pair, same: Bool) {
        pairLabels[pair] = same
        logSimilar()
    }

    var similarRows: [Row] {
        let labelled = pairLabels.compactMap { pair, same in pair.featureDistance.map { ($0, same) } }
        let totalSame = labelled.filter(\.1).count
        return stride(from: Float(0.20), through: 0.90, by: 0.05).map { t in
            let accepted = labelled.filter { $0.0 <= t }
            let correct = accepted.filter(\.1).count
            return Row(threshold: t,
                       precision: accepted.isEmpty ? 1 : Double(correct) / Double(accepted.count),
                       recall: totalSame == 0 ? 0 : Double(correct) / Double(totalSame),
                       n: accepted.count)
        }
    }

    /// Largest threshold that keeps precision at the PRD target (≥ 90 %), with enough
    /// labelled evidence under it.
    var recommendedFeatureThreshold: Float? {
        guard pairLabels.count >= 12 else { return nil }
        return similarRows.filter { $0.precision >= 0.9 && $0.n >= 4 }.map(\.threshold).max()
    }

    // MARK: Blur

    /// Photos from the soft end of the sharpness distribution, where blurry photos are,
    /// plus a few from higher up so there are sharp examples too. (Sampling evenly gave
    /// 1 blurry photo out of 12 labels: not enough to set a threshold.)
    var blurQueue: [(id: String, value: Float)] {
        guard let all = data?.sharpness, !all.isEmpty else { return [] }
        let percentiles = [0.1, 0.3, 0.5, 0.8, 1, 1.3, 1.6, 2, 2.5, 3, 4, 5, 6, 8, 10, 15, 25, 40]
        var seen = Set<String>()
        return percentiles.map { all[min(all.count - 1, Int(Double(all.count) * $0 / 100))] }
            .filter { seen.insert($0.id).inserted && blurLabels[$0.id] == nil }
    }

    func labelBlur(_ id: String, blurry: Bool) {
        blurLabels[id] = blurry
        logBlur()
    }

    /// Threshold (between labelled scores) that best separates blurry from sharp,
    /// preferring the lower value on ties so sharp photos aren't flagged.
    var recommendedBlurThreshold: Float? {
        guard let all = data?.sharpness, blurLabels.count >= 8 else { return nil }
        let scores = Dictionary(all.map { ($0.id, $0.value) }, uniquingKeysWith: { a, _ in a })
        let labelled = blurLabels.compactMap { id, blurry in scores[id].map { ($0, blurry) } }.sorted { $0.0 < $1.0 }
        guard labelled.contains(where: { $0.1 }) else { return nil }
        var best: (Float, Int)?
        for i in 0..<labelled.count {
            let t = i + 1 < labelled.count ? (labelled[i].0 + labelled[i + 1].0) / 2 : labelled[i].0 + 1
            let correct = labelled.filter { ($0.0 < t) == $0.1 }.count
            if best == nil || correct > best!.1 { best = (t, correct) }
        }
        return best?.0
    }

    // MARK: Apply

    func applyFeatureThreshold(_ value: Float) {
        UserDefaults.standard.set(Double(value), forKey: CalibrationKeys.featureThreshold)
        print(String(format: "[calibration] applied featureThreshold=%.2f", value))
        scanStore.scan()
    }

    func applyBlurThreshold(_ value: Float) {
        UserDefaults.standard.set(Double(value), forKey: CalibrationKeys.blurThreshold)
        print(String(format: "[calibration] applied blurThreshold=%.3f", value))
        scanStore.scan()
    }

    func resetOverrides() {
        UserDefaults.standard.removeObject(forKey: CalibrationKeys.featureThreshold)
        UserDefaults.standard.removeObject(forKey: CalibrationKeys.blurThreshold)
        scanStore.scan()
    }

    private func logSimilar() {
        CalibrationReport.logLabels(kind: "similar", similarRows.map { ($0.threshold, $0.precision, $0.recall, $0.n) },
                                    recommended: recommendedFeatureThreshold)
    }

    private func logBlur() {
        guard let all = data?.sharpness else { return }
        let scores = Dictionary(all.map { ($0.id, $0.value) }, uniquingKeysWith: { a, _ in a })
        let points = blurLabels.compactMap { id, blurry in scores[id].map { String(format: "%.3f:%@", $0, blurry ? "B" : "S") } }.sorted()
        print("[calibration] blur labels (score:B=blurry/S=sharp) " + points.joined(separator: " "))
        print("[calibration] blur recommended=\(recommendedBlurThreshold.map { String(format: "%.3f", $0) } ?? "none")")
    }
}

struct CalibrationScreen: View {
    @State private var vm: CalibrationViewModel

    init(env: AppEnvironment) {
        _vm = State(initialValue: CalibrationViewModel(scanStore: env.scanStore))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                InlineBanner(style: .info, systemImage: "lock.shield",
                             message: Text("Debug tool. Your answers and photos stay on this iPhone; only numbers are written to the developer console."))
                Picker("Mode", selection: $vm.mode) {
                    Text("Similar shots").tag(CalibrationViewModel.Mode.similar)
                    Text("Blur").tag(CalibrationViewModel.Mode.blur)
                }
                .pickerStyle(.segmented)

                if let data = vm.data {
                    stats(data)
                    switch vm.mode {
                    case .similar: similar(data)
                    case .blur: blur
                    }
                } else {
                    EmptyState(systemImage: "gauge.with.dots.needle.33percent", title: Text("No scan data yet"),
                               message: Text("Wait for the similar-photo scan to finish, then come back."))
                }
                Button("Reset to built-in thresholds", role: .destructive) { vm.resetOverrides() }
                    .font(Font.sift.caption)
            }
            .padding(Spacing.m)
        }
        .background(Color.sift.canvas)
        .navigationTitle("Calibrate")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stats(_ d: CalibrationData) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("\(d.photos) photos · \(String(format: "%.1f", d.seconds)) s · \(d.groupSizes.count) groups")
                .font(Font.sift.headline)
            Text("\(d.comparisons) time-window comparisons, \(d.comparisonsWithPrints) with Vision prints")
                .font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
            Text(String(format: "Current: similar ≤ %.2f · blur < %.2f", vm.currentFeatureThreshold, vm.currentBlurThreshold))
                .font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
        }
    }

    @ViewBuilder private func similar(_ d: CalibrationData) -> some View {
        Chart {
            ForEach(Array(d.histogram.enumerated()), id: \.offset) { bin, count in
                BarMark(x: .value("Distance", Float(bin) * CalibrationData.binWidth + CalibrationData.binWidth / 2),
                        y: .value("Pairs", count), width: 6)
                    .foregroundStyle(Color.sift.catSimilar)
            }
            RuleMark(x: .value("Threshold", vm.currentFeatureThreshold))
                .foregroundStyle(Color.sift.accent)
                .annotation(position: .top) { Text("now").font(Font.sift.badge) }
        }
        .frame(height: 160)

        if let pair = vm.nextPair {
            VStack(spacing: Spacing.s) {
                Text("Were these taken as the same moment?").font(Font.sift.headline)
                HStack(spacing: Spacing.xs) {
                    ThumbnailView(id: pair.a, pointSize: 200, allowsNetwork: true).aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    ThumbnailView(id: pair.b, pointSize: 200, allowsNetwork: true).aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
                Text(String(format: "distance %.2f · %.0f s apart", pair.featureDistance ?? 0, pair.seconds))
                    .font(Font.sift.caption.monospacedDigit()).foregroundStyle(Color.sift.inkSecondary)
                HStack(spacing: Spacing.xs) {
                    SecondaryButton(title: "Different") { vm.label(pair, same: false) }
                    PrimaryButton(title: "Same moment") { vm.label(pair, same: true) }
                }
                Text("\(vm.pairLabels.count) labelled · \(vm.pairQueue.count) left")
                    .font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
            }
        } else {
            Text("All sample pairs labelled.").font(Font.sift.caption)
        }

        results(rows: vm.similarRows, recommended: vm.recommendedFeatureThreshold, format: "%.2f") {
            vm.applyFeatureThreshold($0)
        }
    }

    @ViewBuilder private var blur: some View {
        if let next = vm.blurQueue.first {
            VStack(spacing: Spacing.s) {
                Text("Is this photo blurry?").font(Font.sift.headline)
                ThumbnailView(id: next.id, pointSize: 400, allowsNetwork: true)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                Text(String(format: "focus score %.2f", next.value))
                    .font(Font.sift.caption.monospacedDigit()).foregroundStyle(Color.sift.inkSecondary)
                HStack(spacing: Spacing.xs) {
                    SecondaryButton(title: "Sharp") { vm.labelBlur(next.id, blurry: false) }
                    PrimaryButton(title: "Blurry") { vm.labelBlur(next.id, blurry: true) }
                }
                Text("\(vm.blurLabels.count) labelled · \(vm.blurQueue.count) left")
                    .font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
            }
        } else {
            Text("All sample photos labelled.").font(Font.sift.caption)
        }
        if let recommended = vm.recommendedBlurThreshold {
            PrimaryButton(title: "Apply blur < \(String(format: "%.2f", recommended))") { vm.applyBlurThreshold(recommended) }
        } else {
            Text("Label at least 8 photos, including a blurry one, for a recommendation.")
                .font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
        }
    }

    @ViewBuilder
    private func results(rows: [CalibrationViewModel.Row], recommended: Float?, format: String,
                         apply: @escaping (Float) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Threshold · precision · recall · pairs").font(Font.sift.badge).foregroundStyle(Color.sift.inkSecondary)
            ForEach(rows.filter { $0.n > 0 }) { row in
                Text(String(format: "\(format)   %3.0f%%   %3.0f%%   %d", row.threshold, row.precision * 100, row.recall * 100, row.n))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(row.threshold == recommended ? Color.sift.accent : Color.sift.inkPrimary)
            }
        }
        if let recommended {
            PrimaryButton(title: "Apply similar ≤ \(String(format: format, recommended))") { apply(recommended) }
        } else {
            Text("Label at least 12 pairs for a recommendation.")
                .font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
        }
    }
}
#else
struct CalibrationScreen: View {
    init(env: AppEnvironment) {}
    var body: some View { EmptyView() }
}
#endif
