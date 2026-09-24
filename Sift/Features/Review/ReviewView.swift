import SwiftUI

/// The Review sheet. Shows exactly what will be removed, then the Summary (FR-REV, FR-SUM).
struct ReviewFlowView: View {
    let env: AppEnvironment
    @State private var vm: ReviewViewModel

    init(env: AppEnvironment) {
        self.env = env
        _vm = State(initialValue: ReviewViewModel(cart: env.cart, deletion: env.deletion, scanStore: env.scanStore, settings: env.settings))
    }

    var body: some View {
        NavigationStack {
            Group {
                if case .finished(let result) = vm.phase {
                    SummaryView(result: result) { env.router.finishCleanup() }
                } else {
                    ReviewView(vm: vm)
                }
            }
            .toolbar {
                if vm.phase == .reviewing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { env.router.sheet = nil }
                    }
                }
            }
        }
        .interactiveDismissDisabled(vm.phase == .deleting)
        .environment(\.thumbnails, env.thumbnails)
    }
}

struct ReviewView: View {
    let vm: ReviewViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Layout.gridGutter), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                totalCard
                if vm.cart.isEmpty {
                    EmptyState(systemImage: "checklist", title: Text("Nothing selected"), message: Text("Pick items to remove from any category."))
                } else {
                    ForEach(vm.sections) { category in section(for: category) }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.sift.canvas)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("You'll free up to")
                .font(Font.sift.caption)
                .foregroundStyle(Color.sift.inkSecondary)
            Text(ByteFormatter.string(vm.cart.totalBytes))
                .font(Font.sift.heroNumber)
                .foregroundStyle(Color.sift.inkPrimary)
                .contentTransition(.numericText())
            Text("^[\(vm.cart.count) item](inflect: true) will be removed. Tap an item to keep it.")
                .font(Font.sift.caption)
                .foregroundStyle(Color.sift.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.sift.hairline))
        .padding(.top, Spacing.s)
        .animation(Motion.standard, value: vm.cart.totalBytes)
    }

    private func section(for category: CleanupCategory) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Circle().fill(category.color).frame(width: 10, height: 10)
                Text(category.title).font(Font.sift.headline).foregroundStyle(Color.sift.inkPrimary)
                Spacer()
                Text(ByteFormatter.string(vm.cart.bytes(in: category)))
                    .font(Font.sift.metric)
                    .foregroundStyle(Color.sift.inkSecondary)
            }
            LazyVGrid(columns: columns, spacing: Layout.gridGutter) {
                ForEach(vm.assetIDs(in: category), id: \.self) { id in
                    Button {
                        withAnimation(Motion.standard) { vm.remove(assetID: id) }
                    } label: {
                        ThumbnailView(id: id, pointSize: 90)
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "minus.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.45))
                                    .padding(4)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Keep this item"))
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: Spacing.s) {
            InlineBanner(
                style: .info,
                systemImage: "trash",
                message: Text("Photos and videos go to Recently Deleted in the Photos app. The space comes back once you empty it, or automatically after 30 days.")
            )
            PrimaryButton(
                title: "Delete ^[\(vm.cart.count) item](inflect: true) · \(ByteFormatter.string(vm.cart.totalBytes))",
                systemImage: "trash",
                role: .destructive,
                isLoading: vm.phase == .deleting
            ) {
                Task { await vm.confirm() }
            }
            .disabled(vm.cart.isEmpty)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xs)
        .background(Color.sift.canvas.opacity(0.97))
    }
}
