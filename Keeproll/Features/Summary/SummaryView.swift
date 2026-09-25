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
                            Image(systemName: category.symbol).font(.title3.weight(.medium)).foregroundStyle(category.color).frame(width: 28)
                            Text(category.title)
                            Spacer()
                            Text("^[\(result.countsByCategory[category] ?? 0) item](inflect: true)")
                                .font(Font.keeproll.metric)
                                .foregroundStyle(Color.keeproll.inkSecondary)
                        }
                        .font(Font.keeproll.body)
                        .foregroundStyle(Color.keeproll.inkPrimary)
                        .padding(.vertical, Spacing.s)
                        .overlay(alignment: .bottom) { Divider().overlay(Color.keeproll.hairline) }
                    }
                }

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
                                .font(Font.keeproll.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(Color.keeproll.accent)
                                .background(Color.keeproll.accentSoft, in: Capsule())
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
        .background(Color.keeproll.canvas)
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

    /// One check that scales in. No rings, no glow.
    private var successMark: some View {
        let color = succeeded ? Color.keeproll.success : Color.keeproll.warning
        return Image(systemName: succeeded ? "checkmark.circle" : "exclamationmark.circle")
            .font(.system(.largeTitle, weight: .light))
            .imageScale(.large)
            .foregroundStyle(color)
            .scaleEffect(appeared ? 1 : 0.6)
            .animation(Motion.standard, value: appeared)
            .frame(height: 96)
            .accessibilityHidden(true)
    }
}
