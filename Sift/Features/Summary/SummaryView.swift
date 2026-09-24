import SwiftUI

/// Shown after cleaning: space freed, what was removed, and the Recently Deleted reminder (FR-SUM-1).
struct SummaryView: View {
    let result: CleanupResult
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownBytes: Int64 = 0
    @State private var appeared = false

    private var succeeded: Bool { result.failures.isEmpty }
    private var photosRemoved: Bool { !result.deletedAssetIDs.isEmpty }

    /// Contacts and events have no size, so the hero counts them instead.
    private var recordCount: Text {
        let contacts = result.countsByCategory[.contacts] ?? 0
        let events = result.countsByCategory[.calendar] ?? 0
        if events == 0 { return Text("^[\(contacts) contact](inflect: true)") }
        if contacts == 0 { return Text("^[\(events) event](inflect: true)") }
        return Text("^[\(contacts + events) change](inflect: true)")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                successMark
                    .padding(.top, Spacing.xxl)

                VStack(spacing: Spacing.xxs) {
                    if photosRemoved {
                        Text(ByteFormatter.string(shownBytes))
                            .font(Font.sift.heroNumber)
                            .foregroundStyle(Color.sift.inkPrimary)
                            .contentTransition(.numericText())
                    } else {
                        recordCount
                            .font(Font.sift.heroNumber)
                            .foregroundStyle(Color.sift.inkPrimary)
                    }
                    Text(photosRemoved ? "cleaned up" : "tidied up")
                        .font(Font.sift.body)
                        .foregroundStyle(Color.sift.inkSecondary)
                }
                .accessibilityElement(children: .combine)

                VStack(spacing: 0) {
                    ForEach(CleanupCategory.allCases.filter { (result.countsByCategory[$0] ?? 0) > 0 }) { category in
                        HStack(spacing: Spacing.s) {
                            Image(systemName: category.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(category.color, in: RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                            Text(category.title)
                            Spacer()
                            Text("^[\(result.countsByCategory[category] ?? 0) item](inflect: true)")
                                .font(Font.sift.metric)
                                .foregroundStyle(Color.sift.inkSecondary)
                        }
                        .font(Font.sift.body)
                        .foregroundStyle(Color.sift.inkPrimary)
                        .padding(Spacing.m)
                    }
                }
                .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.sift.hairline))

                if !succeeded {
                    InlineBanner(
                        style: .warning,
                        systemImage: "exclamationmark.triangle",
                        message: Text("^[\(result.failures.count) item](inflect: true) couldn't be removed. They're still in your review list.")
                    )
                }

                if !result.backupURLs.isEmpty {
                    InlineBanner(style: .info, systemImage: "externaldrive.badge.checkmark",
                                 message: Text("A backup of the changed contacts and events was saved before anything changed.")) {
                        ShareLink(items: result.backupURLs) {
                            Label("Share backup", systemImage: "square.and.arrow.up")
                                .font(Font.sift.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(Color.sift.accent)
                                .background(Color.sift.accentSoft, in: Capsule())
                        }
                    }
                }

                if photosRemoved {
                    InlineBanner(
                        style: .info,
                        systemImage: "trash",
                        message: Text("Deleted photos stay in Recently Deleted for 30 days. Empty it in the Photos app to get the space back now.")
                    ) {
                        SecondaryButton(title: "Open Photos", systemImage: "photo.on.rectangle") { SystemActions.openPhotos() }
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
        }
        .background(Color.sift.canvas)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Done", action: onDone)
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.xs)
        }
        .navigationTitle("All done")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(reduceMotion ? nil : Motion.gentle) { appeared = true }
            withAnimation(reduceMotion ? nil : Motion.countUp.delay(0.2)) { shownBytes = result.bytesFreed }
        }
    }

    /// Concentric rings that expand out from the check.
    private var successMark: some View {
        let color = succeeded ? Color.sift.success : Color.sift.warning
        return ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(color.opacity(0.22 - Double(ring) * 0.06), lineWidth: 1.5)
                    .frame(width: 96 + CGFloat(ring) * 40, height: 96 + CGFloat(ring) * 40)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .animation(Motion.gentle.delay(Double(ring) * 0.08), value: appeared)
            }
            Circle()
                .fill(color.opacity(0.14))
                .frame(width: 96, height: 96)
            Image(systemName: succeeded ? "checkmark" : "exclamationmark")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(color)
                .scaleEffect(appeared ? 1 : 0.4)
                .animation(Motion.standard.delay(0.1), value: appeared)
        }
        .frame(height: 180)
        .accessibilityHidden(true)
    }
}
