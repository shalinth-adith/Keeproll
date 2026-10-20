import StoreKit
import SwiftUI

/// Shown after cleaning: space freed, what was removed, and the Recently Deleted reminder (FR-SUM-1).
struct SummaryView: View {
    let result: CleanupResult
    /// Session count and the once-only review flag live here.
    var settings: SettingsStore? = nil
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.requestReview) private var requestReview
    @State private var shareImage: ShareCardImage?
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
                            .font(Font.keeproll.heroNumber)
                            .foregroundStyle(Color.keeproll.inkPrimary)
                            .contentTransition(.numericText())
                    } else {
                        recordCount
                            .font(Font.keeproll.heroNumber)
                            .foregroundStyle(Color.keeproll.inkPrimary)
                    }
                    Text(photosRemoved ? "cleaned up" : "tidied up")
                        .font(Font.keeproll.body)
                        .foregroundStyle(Color.keeproll.inkSecondary)
                }
                .accessibilityElement(children: .combine)

                VStack(spacing: 0) {
                    ForEach(CleanupCategory.allCases.filter { (result.countsByCategory[$0] ?? 0) > 0 }) { category in
                        HStack(spacing: Spacing.s) {
                            CategoryTile(category: category, side: 32)
                            Text(category.title)
                            Spacer()
                            Text("^[\(result.countsByCategory[category] ?? 0) item](inflect: true)")
                                .font(Font.keeproll.metric)
                                .foregroundStyle(Color.keeproll.inkSecondary)
                        }
                        .font(Font.keeproll.body)
                        .foregroundStyle(Color.keeproll.inkPrimary)
                        .padding(.vertical, Spacing.s)
                        if category != CleanupCategory.allCases.filter({ (result.countsByCategory[$0] ?? 0) > 0 }).last {
                            Divider().overlay(Color.keeproll.hairline)
                        }
                    }
                }
                .card(padding: Spacing.s)

                if !succeeded {
                    InlineBanner(
                        style: .warning,
                        systemImage: "exclamationmark.triangle",
                        message: Text("^[\(result.failures.count) item](inflect: true) couldn't be removed. They're still in your review list.")
                    )
                }

                if !result.backupURLs.isEmpty {
                    InlineBanner(style: .info, systemImage: "clock.arrow.circlepath",
                                 message: Text("A backup was saved before anything changed. You can also find it later in Settings, under Backups.")) {
                        Button { ActivityShare.present(result.backupURLs) } label: {
                            Label("Share backup", systemImage: "square.and.arrow.up")
                                .font(Font.keeproll.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(Color.keeproll.accent)
                                .background(Color.keeproll.accentSoft, in: Capsule())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }

                if photosRemoved {
                    InlineBanner(
                        style: .info,
                        systemImage: "trash",
                        message: Text("Deleted photos stay in Recently Deleted for 30 days. To get the space back now, open Photos, go to Recently Deleted under Utilities, and delete them there.")
                    )
                }
            }
            .padding(.horizontal, Spacing.m)
        }
        .background(Color.keeproll.canvas)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.s) {
                if photosRemoved, let shareImage {
                    // The only growth loop a no-network app has: an honest card, user-initiated.
                    Button {
                        if let file = ShareCard.file(for: shareImage.image) { ActivityShare.present([file]) }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(Font.keeproll.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(Color.keeproll.accent)
                            .background(Color.keeproll.accentSoft, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                PrimaryButton(title: "Done", action: onDone)
            }
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
            if photosRemoved, let image = ShareCard.image(bytesFreed: result.bytesFreed, itemCount: result.deletedAssetIDs.count) {
                shareImage = ShareCardImage(image: image)
            }
            maybeAskForReview()
        }
    }

    /// Once per install, after a good cleanup, never in the first session (ReviewPrompter).
    /// The sheet appears after the count-up so it doesn't cover the result.
    private func maybeAskForReview() {
        guard let settings,
              ReviewPrompter.shouldAsk(bytesFreed: result.bytesFreed, sessionCount: settings.sessionCount,
                                       alreadyAsked: settings.hasAskedForReview, failures: result.failures.count) else { return }
        settings.markReviewAsked()
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            requestReview()
        }
    }

    /// Concentric rings that expand out from the check.
    private var successMark: some View {
        let color = succeeded ? Color.keeproll.success : Color.keeproll.warning
        return ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(color.opacity(0.22 - Double(ring) * 0.06), lineWidth: 1.5)
                    .frame(width: 96 + CGFloat(ring) * 40, height: 96 + CGFloat(ring) * 40)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .animation(Motion.gentle.delay(Double(ring) * 0.08), value: appeared)
            }
            Circle().fill(color.opacity(0.14)).frame(width: 96, height: 96)
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
