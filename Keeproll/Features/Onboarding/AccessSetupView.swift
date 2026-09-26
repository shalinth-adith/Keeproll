import Observation
import SwiftUI

/// Onboarding page 2: every permission in one place. "Allow all" walks through the
/// three system prompts in order; each row can also be allowed on its own. Nothing here
/// blocks the user: "Not now" still enters the app (FR-PERM-1…3).
@Observable
final class AccessSetupViewModel {
    enum Item: CaseIterable, Identifiable {
        case photos, contacts, calendar
        var id: Self { self }
    }

    private let scanStore: ScanStore
    private(set) var requesting: Item?

    init(scanStore: ScanStore) { self.scanStore = scanStore }

    func state(_ item: Item) -> PermissionState {
        switch item {
        case .photos: scanStore.photosPermission
        case .contacts: scanStore.contactsPermission
        case .calendar: scanStore.calendarPermission
        }
    }

    /// Every prompt has been answered one way or another.
    var allDecided: Bool { Item.allCases.allSatisfy { state($0) != .notDetermined } }
    var anyGranted: Bool { Item.allCases.contains { state($0).canRead } }

    func request(_ item: Item) async {
        guard state(item) == .notDetermined else { SystemActions.openSettings(); return }
        requesting = item
        switch item {
        case .photos: await scanStore.requestPhotos()
        case .contacts: await scanStore.requestContacts()
        case .calendar: await scanStore.requestCalendar()
        }
        requesting = nil
    }

    /// Photos first (it matters most), then contacts, then calendar. Skips decided ones.
    func requestAll() async {
        for item in Item.allCases where state(item) == .notDetermined {
            await request(item)
        }
    }
}

struct AccessSetupPage: View {
    @State private var vm: AccessSetupViewModel
    let onFinish: () -> Void

    init(scanStore: ScanStore, onFinish: @escaping () -> Void) {
        _vm = State(initialValue: AccessSetupViewModel(scanStore: scanStore))
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: 0)
            OnboardingHero.Access()
            VStack(spacing: Spacing.xs) {
                Text("Set up access")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.keeproll.inkPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Keeproll reads these on your iPhone only. Nothing is uploaded, and nothing is removed until you confirm on Review.")
                    .font(Font.keeproll.body)
                    .foregroundStyle(Color.keeproll.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(AccessSetupViewModel.Item.allCases.enumerated()), id: \.element) { index, item in
                    row(item)
                    if index < AccessSetupViewModel.Item.allCases.count - 1 {
                        Divider().overlay(Color.keeproll.hairline).padding(.leading, 36 + Spacing.s)
                    }
                }
            }
            .card()
            Spacer(minLength: 0)
            VStack(spacing: Spacing.s) {
                if vm.allDecided {
                    PrimaryButton(title: "Start using Keeproll", systemImage: "arrow.right", action: onFinish)
                } else {
                    PrimaryButton(title: "Allow all", systemImage: "checkmark.shield", isLoading: vm.requesting != nil) {
                        Task { await vm.requestAll() }
                    }
                    Button("Not now", action: onFinish)
                        .font(Font.keeproll.headline)
                        .foregroundStyle(Color.keeproll.inkSecondary)
                        .frame(minHeight: Layout.minTouchTarget)
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.l)
        .animation(Motion.standard, value: vm.allDecided)
    }

    private func row(_ item: AccessSetupViewModel.Item) -> some View {
        let state = vm.state(item)
        return HStack(spacing: Spacing.s) {
            Image(systemName: symbol(item))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(KeeprollGradient.tile(tint(item)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(item)).font(Font.keeproll.headline).foregroundStyle(Color.keeproll.inkPrimary)
                Text(reason(item)).font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.s)
            trailing(item, state)
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func trailing(_ item: AccessSetupViewModel.Item, _ state: PermissionState) -> some View {
        if vm.requesting == item {
            ProgressView().controlSize(.small)
        } else if state.canRead {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.keeproll.success)
                .accessibilityLabel(Text("Allowed"))
        } else if state == .notDetermined {
            Button("Allow") { Task { await vm.request(item) } }
                .font(Font.keeproll.caption.weight(.semibold))
                .foregroundStyle(Color.keeproll.accent)
                .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xs)
                .background(Color.keeproll.accentSoft, in: Capsule())
                .buttonStyle(.plain)
        } else {
            Button("Settings") { SystemActions.openSettings() }
                .font(Font.keeproll.caption.weight(.semibold))
                .foregroundStyle(Color.keeproll.inkSecondary)
                .buttonStyle(.plain)
        }
    }

    private func symbol(_ item: AccessSetupViewModel.Item) -> String {
        switch item { case .photos: "photo.on.rectangle"; case .contacts: "person.2"; case .calendar: "calendar" }
    }
    private func tint(_ item: AccessSetupViewModel.Item) -> Color {
        switch item { case .photos: Color.keeproll.catSimilar; case .contacts: Color.keeproll.catContacts; case .calendar: Color.keeproll.catCalendar }
    }
    private func title(_ item: AccessSetupViewModel.Item) -> LocalizedStringResource {
        switch item { case .photos: "Photos"; case .contacts: "Contacts"; case .calendar: "Calendar" }
    }
    private func reason(_ item: AccessSetupViewModel.Item) -> LocalizedStringResource {
        switch item {
        case .photos: "Similar shots, screenshots, blurry photos and large videos"
        case .contacts: "The same person saved more than once"
        case .calendar: "Duplicate events and events over a year old"
        }
    }
}
