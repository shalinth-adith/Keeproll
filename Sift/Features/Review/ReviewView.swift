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
                    ForEach(vm.sections) { category in
                        if category == .contacts || category == .calendar { recordSection(category) } else { section(for: category) }
                    }
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
            Text(vm.mediaCount > 0 ? "You'll free up to" : "You're about to tidy")
                .font(Font.sift.caption)
                .foregroundStyle(Color.sift.inkSecondary)
            // Separate literals: inflection only renders inside a `Text` literal, not a String.
            Group {
                if vm.mediaCount > 0 {
                    Text(ByteFormatter.string(vm.cart.totalBytes))
                } else {
                    Text("^[\(vm.recordChangeCount) change](inflect: true)")
                }
            }
                .font(Font.sift.heroNumber)
                .foregroundStyle(Color.sift.inkPrimary)
                .contentTransition(.numericText())
            summaryLine
                .font(Font.sift.caption)
                .foregroundStyle(Color.sift.inkSecondary)
            if vm.cloudOnly.count > 0 {
                Label {
                    Text("^[\(vm.cloudOnly.count) item](inflect: true) (\(ByteFormatter.string(vm.cloudOnly.bytes))) are only in iCloud. Removing them frees iCloud space, not iPhone storage.")
                } icon: {
                    Image(systemName: "icloud")
                }
                .font(Font.sift.caption)
                .foregroundStyle(Color.sift.warning)
                .padding(.top, Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.sift.hairline))
        .padding(.top, Spacing.s)
        .animation(Motion.standard, value: vm.cart.totalBytes)
    }

    /// Built from `Text` pieces so automatic grammar agreement applies to each count.
    private var summaryLine: Text {
        var line = Text("")
        if vm.mediaCount > 0 { line = Text("^[\(vm.mediaCount) item](inflect: true) from Photos will be removed") }
        if vm.contactActionCount > 0 {
            let contacts = Text("^[\(vm.contactActionCount) contact change](inflect: true)")
            line = vm.mediaCount > 0 ? line + Text(" · ") + contacts : contacts
        }
        if vm.calendarEventCount > 0 {
            let events = Text("^[\(vm.calendarEventCount) calendar event](inflect: true) to remove")
            line = vm.mediaCount + vm.contactActionCount > 0 ? line + Text(" · ") + events : events
        }
        return line + Text(". ") + Text("Tap an item to keep it.")
    }

    /// Contacts and calendar events: rows, not thumbnails, and backed up before changes.
    private func recordSection(_ category: CleanupCategory) -> some View {
        let rows = vm.recordItems(in: category)
        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Circle().fill(category.color).frame(width: 10, height: 10)
                Text(category.title).font(Font.sift.headline).foregroundStyle(Color.sift.inkPrimary)
                Spacer()
                Text("Backed up first").font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.key) { index, item in
                    HStack(spacing: Spacing.s) {
                        switch item {
                        case .contactMerge(_, _, let mergedIDs, let name):
                            Image(systemName: "arrow.triangle.merge").foregroundStyle(Color.sift.accent).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(Font.sift.headline).foregroundStyle(Color.sift.inkPrimary)
                                Text("Merge ^[\(mergedIDs.count + 1) contact](inflect: true) into one").font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
                            }
                        case .contactDelete(_, let name):
                            Image(systemName: "person.crop.circle.badge.minus").foregroundStyle(Color.sift.destructive).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(Font.sift.headline).foregroundStyle(Color.sift.inkPrimary)
                                Text("Delete contact").font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
                            }
                        case .calendarEvent(_, let title, let start):
                            Image(systemName: "calendar.badge.minus").foregroundStyle(Color.sift.destructive).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title.isEmpty ? String(localized: "Untitled event") : title)
                                    .font(Font.sift.headline).foregroundStyle(Color.sift.inkPrimary).lineLimit(2)
                                Text(start?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Unknown date"))
                                    .font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
                            }
                        case .asset: EmptyView()
                        }
                        Spacer()
                        Button { withAnimation(Motion.standard) { vm.remove(item) } } label: {
                            Image(systemName: "minus.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.sift.inkTertiary, Color.sift.canvas)
                                .font(.title3)
                                .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Keep as is"))
                    }
                    .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.xs)
                    if index < rows.count - 1 { Divider().overlay(Color.sift.hairline).padding(.leading, Spacing.m) }
                }
            }
            .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.sift.hairline))
        }
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
            if category == .vault {
                Label("Copies of these are safe in your vault. This removes the originals from your library.", systemImage: "lock.shield")
                    .font(Font.sift.caption)
                    .foregroundStyle(Color.sift.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                systemImage: vm.mediaCount == 0 ? "externaldrive.badge.checkmark" : "trash",
                message: Text(vm.mediaCount == 0
                    ? "Sift saves a backup before changing any contact or event. They have no Recently Deleted, so the backup is your undo."
                    : vm.recordChangeCount > 0
                    ? "Photos and videos go to Recently Deleted for 30 days. Contacts and events are backed up in Sift before they change."
                    : "Photos and videos go to Recently Deleted in the Photos app. The space comes back once you empty it, or automatically after 30 days.")
            )
            PrimaryButton(
                title: vm.mediaCount > 0
                    ? "Confirm ^[\(vm.cart.count) item](inflect: true) · \(ByteFormatter.string(vm.cart.totalBytes))"
                    : "Confirm ^[\(vm.cart.count) change](inflect: true)",
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
