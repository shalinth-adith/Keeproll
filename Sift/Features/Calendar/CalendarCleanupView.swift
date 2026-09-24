import Observation
import SwiftUI

/// Old and duplicate calendar events (bonus: calendar cleanup). Selecting only adds to
/// the cart; events are removed on Review, after an .ics backup (D10, D11).
@Observable
final class CalendarCleanupViewModel {
    private let scanStore: ScanStore
    private let cart: CleanupCart

    init(scanStore: ScanStore, cart: CleanupCart) {
        self.scanStore = scanStore
        self.cart = cart
    }

    var permission: PermissionState { scanStore.calendarPermission }
    var findings: CalendarFindings { scanStore.calendar.value ?? CalendarFindings() }
    var isLoading: Bool { scanStore.calendar.isLoading }
    var selectedCount: Int { cart.count(in: .calendar) }

    /// Old events grouped by the year they happened, newest year first.
    var oldEventsByYear: [(year: Int, events: [CalendarEventSummary])] {
        let grouped = Dictionary(grouping: findings.oldEvents) { event in
            Calendar.current.component(.year, from: event.start ?? .distantPast)
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    func isSelected(_ event: CalendarEventSummary) -> Bool { cart.contains(Self.item(event)) }

    func toggle(_ event: CalendarEventSummary) { cart.toggle(Self.item(event)) }

    func allSelected(_ events: [CalendarEventSummary]) -> Bool {
        !events.isEmpty && events.allSatisfy { cart.contains(Self.item($0)) }
    }

    /// Selects every event in the list, or clears them if all are selected.
    func toggleAll(_ events: [CalendarEventSummary]) {
        if allSelected(events) {
            events.forEach { cart.remove(Self.item($0)) }
        } else {
            cart.add(events.map(Self.item))
        }
    }

    func requestAccess() async {
        if permission == .notDetermined {
            await scanStore.requestCalendar()
            scanStore.scan()
        } else {
            SystemActions.openSettings()
        }
    }

    static func item(_ event: CalendarEventSummary) -> CartItem {
        .calendarEvent(id: event.id, title: event.title, start: event.start)
    }
}

struct CalendarCleanupView: View {
    @State private var vm: CalendarCleanupViewModel

    init(env: AppEnvironment) {
        _vm = State(initialValue: CalendarCleanupViewModel(scanStore: env.scanStore, cart: env.cart))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.m) {
                if !vm.permission.canRead {
                    locked
                } else {
                    header
                    if vm.findings.isEmpty && !vm.isLoading {
                        EmptyState(systemImage: "calendar", title: Text("Nothing to tidy"),
                                   message: Text("No duplicate events, and nothing older than a year."))
                    } else {
                        if !vm.findings.duplicateGroups.isEmpty { duplicates }
                        if !vm.findings.oldEvents.isEmpty { oldEvents }
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.sift.canvas)
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if vm.isLoading && vm.findings.isEmpty && vm.permission.canRead { ProgressView() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("^[\(vm.findings.suggestionCount) event](inflect: true)")
                        .font(Font.sift.heroNumber)
                        .foregroundStyle(Color.sift.inkPrimary)
                        .contentTransition(.numericText())
                    Text("duplicates and events over a year old")
                        .font(Font.sift.caption)
                        .foregroundStyle(Color.sift.inkSecondary)
                }
                Spacer()
                if vm.selectedCount > 0 {
                    Text("\(vm.selectedCount) selected")
                        .font(Font.sift.caption.weight(.semibold))
                        .foregroundStyle(Color.sift.accent)
                        .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xxs)
                        .background(Color.sift.accentSoft, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            InlineBanner(style: .info, systemImage: "externaldrive.badge.checkmark",
                         message: Text("Repeating events are never touched. Sift saves a calendar backup before removing anything; open it in Calendar to restore."))
        }
        .padding(.top, Spacing.s)
        .animation(Motion.standard, value: vm.selectedCount)
    }

    private var duplicates: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Duplicate events").font(Font.sift.title).foregroundStyle(Color.sift.inkPrimary)
            ForEach(vm.findings.duplicateGroups, id: \.first?.id) { group in
                let extras = Array(group.dropFirst())
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group[0].title).font(Font.sift.headline).foregroundStyle(Color.sift.inkPrimary)
                            Text("\(dateText(group[0])) · ^[\(group.count) copy](inflect: true)")
                                .font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
                        }
                        Spacer()
                        Button(vm.allSelected(extras) ? "Keep all" : "Keep one") { vm.toggleAll(extras) }
                            .font(Font.sift.caption.weight(.semibold))
                            .foregroundStyle(Color.sift.accent)
                            .buttonStyle(.plain)
                            .frame(minHeight: Layout.minTouchTarget)
                    }
                    ForEach(Array(group.enumerated()), id: \.element.id) { index, event in
                        if index == 0 {
                            HStack(spacing: Spacing.s) {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.sift.success).frame(width: 28)
                                Text("Keep · \(event.calendarTitle)").font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
                            }
                        } else {
                            row(event, detail: Text(event.calendarTitle))
                        }
                    }
                }
                .padding(Spacing.m)
                .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.sift.hairline))
            }
        }
    }

    private var oldEvents: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Older than a year").font(Font.sift.title).foregroundStyle(Color.sift.inkPrimary)
                .padding(.top, Spacing.s)
            ForEach(vm.oldEventsByYear, id: \.year) { year, events in
                DisclosureGroup {
                    VStack(spacing: 0) {
                        ForEach(events) { event in row(event, detail: Text(dateText(event))) }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(year)).font(Font.sift.headline).foregroundStyle(Color.sift.inkPrimary)
                            Text("^[\(events.count) event](inflect: true)").font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
                        }
                        Spacer()
                        Button(vm.allSelected(events) ? "Deselect" : "Select year") { vm.toggleAll(events) }
                            .font(Font.sift.caption.weight(.semibold))
                            .foregroundStyle(Color.sift.accent)
                            .buttonStyle(.plain)
                            .frame(minHeight: Layout.minTouchTarget)
                    }
                }
                .tint(Color.sift.inkSecondary)
                .padding(Spacing.m)
                .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.sift.hairline))
            }
        }
    }

    private func row(_ event: CalendarEventSummary, detail: Text) -> some View {
        let selected = vm.isSelected(event)
        return Button { vm.toggle(event) } label: {
            HStack(spacing: Spacing.s) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.sift.accent : Color.sift.inkTertiary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title.isEmpty ? String(localized: "Untitled event") : event.title)
                        .font(Font.sift.body).foregroundStyle(Color.sift.inkPrimary).lineLimit(2)
                    detail.font(Font.sift.caption).foregroundStyle(Color.sift.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: Layout.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dateText(_ event: CalendarEventSummary) -> String {
        guard let start = event.start else { return String(localized: "Unknown date") }
        return event.isAllDay ? start.formatted(date: .abbreviated, time: .omitted)
                              : start.formatted(date: .abbreviated, time: .shortened)
    }

    private var locked: some View {
        EmptyState(systemImage: "calendar.badge.exclamationmark", title: Text("Calendar access needed"),
                   message: Text("Sift looks for duplicate events and events over a year old. Nothing is uploaded, and nothing is removed until you confirm on Review.")) {
            PrimaryButton(title: vm.permission == .notDetermined ? "Allow access" : "Open Settings") {
                Task { await vm.requestAccess() }
            }
            .padding(.top, Spacing.s)
        }
        .padding(.top, Spacing.xxxl)
    }
}
