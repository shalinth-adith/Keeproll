import SwiftUI

/// Shown after cleaning: space freed, what was removed, and the Recently Deleted reminder (FR-SUM-1).
struct SummaryView: View {
    let result: CleanupResult
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownBytes: Int64 = 0
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(result.failures.isEmpty ? Color.sift.success : Color.sift.warning)
                    .symbolEffect(.bounce, value: appeared)
                    .accessibilityHidden(true)
                    .padding(.top, Spacing.xxl)

                VStack(spacing: Spacing.xxs) {
                    Text(ByteFormatter.string(shownBytes))
                        .font(Font.sift.heroNumber)
                        .foregroundStyle(Color.sift.inkPrimary)
                        .contentTransition(.numericText())
                    Text("cleaned up")
                        .font(Font.sift.body)
                        .foregroundStyle(Color.sift.inkSecondary)
                }
                .accessibilityElement(children: .combine)

                VStack(spacing: 0) {
                    ForEach(CleanupCategory.allCases.filter { (result.countsByCategory[$0] ?? 0) > 0 }) { category in
                        HStack {
                            Image(systemName: category.symbol).foregroundStyle(category.color)
                            Text(category.title)
                            Spacer()
                            Text("\(result.countsByCategory[category] ?? 0)").font(Font.sift.metric)
                        }
                        .font(Font.sift.body)
                        .foregroundStyle(Color.sift.inkPrimary)
                        .padding(Spacing.m)
                    }
                }
                .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                if !result.failures.isEmpty {
                    InlineBanner(
                        style: .warning,
                        systemImage: "exclamationmark.triangle",
                        message: Text("^[\(result.failures.count) item](inflect: true) couldn't be removed. They're still in your review list.")
                    )
                }

                InlineBanner(
                    style: .info,
                    systemImage: "trash",
                    message: Text("Deleted photos stay in Recently Deleted for 30 days. Empty it in the Photos app to get the space back now.")
                ) {
                    SecondaryButton(title: "Open Photos", systemImage: "photo.on.rectangle") { SystemActions.openPhotos() }
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
            appeared = true
            withAnimation(reduceMotion ? nil : Motion.countUp) { shownBytes = result.bytesFreed }
        }
    }
}
