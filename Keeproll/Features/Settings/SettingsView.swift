import Observation
import SwiftUI

/// Settings: permission status, data kept on the device, and about (DESIGN_SYSTEM §9).
/// Everything here is local; there is nothing to sign in to and nothing to sync.
@Observable
final class SettingsViewModel {
    private let scanStore: ScanStore
    let settings: SettingsStore
    private(set) var cacheCleared = false

    init(scanStore: ScanStore, settings: SettingsStore) {
        self.scanStore = scanStore
        self.settings = settings
    }

    var photos: PermissionState { scanStore.photosPermission }
    var contacts: PermissionState { scanStore.contactsPermission }
    var calendar: PermissionState { scanStore.calendarPermission }

    var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// First request goes through the system prompt; after that only Settings can change it.
    func request(_ kind: CleanupCategory) async {
        switch kind {
        case .contacts where contacts == .notDetermined:
            await scanStore.requestContacts(); scanStore.scan()
        case .calendar where calendar == .notDetermined:
            await scanStore.requestCalendar(); scanStore.scan()
        case .similar, .screenshots, .blurry, .videos:
            if photos == .notDetermined { await scanStore.requestPhotos(); scanStore.scan() } else { SystemActions.openSettings() }
        default:
            SystemActions.openSettings()
        }
    }

    /// Deletes the on-device feature cache; the next scan recomputes everything.
    func clearCache() {
        try? FileManager.default.removeItem(at: ScanCache.defaultURL)
        cacheCleared = true
        Log.ui.debug("Scan cache cleared from Settings")
    }

    func resetFreedTotal() { settings.resetFreedTotal() }

    func replayOnboarding() { settings.hasCompletedOnboarding = false }
}

struct SettingsView: View {
    @State private var vm: SettingsViewModel
    @State private var confirmCache = false
    @State private var confirmReset = false

    init(env: AppEnvironment) {
        _vm = State(initialValue: SettingsViewModel(scanStore: env.scanStore, settings: env.settings))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                section(Text("Access")) {
                    permissionRow(symbol: "photo.on.rectangle", tint: Color.keeproll.catSimilar, title: Text("Photos"), state: vm.photos) {
                        Task { await vm.request(.similar) }
                    }
                    Divider().overlay(Color.keeproll.hairline).padding(.leading, 36 + Spacing.s)
                    permissionRow(symbol: "person.2", tint: Color.keeproll.catContacts, title: Text("Contacts"), state: vm.contacts) {
                        Task { await vm.request(.contacts) }
                    }
                    Divider().overlay(Color.keeproll.hairline).padding(.leading, 36 + Spacing.s)
                    permissionRow(symbol: "calendar", tint: Color.keeproll.catCalendar, title: Text("Calendar"), state: vm.calendar) {
                        Task { await vm.request(.calendar) }
                    }
                }
                HintRow("lock.shield", Text("Keeproll reads these on your iPhone only. Nothing is uploaded, and nothing is removed until you confirm on Review."))

                section(Text("Data on this iPhone")) {
                    actionRow(symbol: "internaldrive", tint: Color.keeproll.catVault, title: Text("Clear scan cache"),
                              subtitle: Text(vm.cacheCleared ? "Cleared. The next scan will take longer." : "Photo features kept so rescans take seconds. Safe to clear.")) {
                        confirmCache = true
                    }
                    Divider().overlay(Color.keeproll.hairline).padding(.leading, 36 + Spacing.s)
                    actionRow(symbol: "leaf", tint: Color.keeproll.success, title: Text("Reset freed total"),
                              subtitle: Text("Currently \(ByteFormatter.string(vm.settings.lifetimeBytesFreed))")) {
                        confirmReset = true
                    }
                    Divider().overlay(Color.keeproll.hairline).padding(.leading, 36 + Spacing.s)
                    actionRow(symbol: "sparkles.rectangle.stack", tint: Color.keeproll.accent, title: Text("Show the welcome again"),
                              subtitle: Text("Replays the three onboarding pages.")) {
                        vm.replayOnboarding()
                    }
                }

                section(Text("About")) {
                    infoRow(title: Text("Version"), value: Text(vm.version))
                    Divider().overlay(Color.keeproll.hairline)
                    infoRow(title: Text("Made for"), value: Text("AppFactory App Builder task"))
                    Divider().overlay(Color.keeproll.hairline)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Privacy").font(Font.keeproll.headline).foregroundStyle(Color.keeproll.inkPrimary)
                        Text("Keeproll has no account, no analytics and no network access. Photos, contacts and events are read on this iPhone and never leave it. Contacts and calendar changes are backed up to a file you can share before anything is changed.")
                            .font(Font.keeproll.caption)
                            .foregroundStyle(Color.keeproll.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.keeproll.canvas)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear the scan cache?", isPresented: $confirmCache, titleVisibility: .visible) {
            Button("Clear cache") { vm.clearCache() }
        } message: {
            Text("Nothing in your library changes. The next scan recomputes photo features, so it takes as long as the first one did.")
        }
        .confirmationDialog("Reset the freed total?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset to zero", role: .destructive) { vm.resetFreedTotal() }
        }
    }

    private func section<Content: View>(_ title: Text, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            title.font(Font.keeproll.title).foregroundStyle(Color.keeproll.inkPrimary).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content() }.card(padding: Spacing.m)
        }
    }

    private func permissionRow(symbol: String, tint: Color, title: Text, state: PermissionState, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Image(systemName: symbol).font(.headline.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(KeeprollGradient.tile(tint), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    title.font(Font.keeproll.headline).foregroundStyle(Color.keeproll.inkPrimary)
                    Text(label(for: state)).font(Font.keeproll.caption).foregroundStyle(color(for: state))
                }
                Spacer(minLength: Spacing.s)
                Text(state.canRead && state != .limited ? "" : (state == .notDetermined ? "Allow" : "Change"))
                    .font(Font.keeproll.caption.weight(.semibold))
                    .foregroundStyle(Color.keeproll.accent)
                Image(systemName: "chevron.right").font(Font.keeproll.caption.weight(.bold)).foregroundStyle(Color.keeproll.inkTertiary)
            }
            .padding(.vertical, Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func actionRow(symbol: String, tint: Color, title: Text, subtitle: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Image(systemName: symbol).font(.headline.weight(.semibold)).foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    title.font(Font.keeproll.headline).foregroundStyle(Color.keeproll.inkPrimary)
                    subtitle.font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer(minLength: Spacing.s)
                Image(systemName: "chevron.right").font(Font.keeproll.caption.weight(.bold)).foregroundStyle(Color.keeproll.inkTertiary)
            }
            .padding(.vertical, Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func infoRow(title: Text, value: Text) -> some View {
        HStack {
            title.font(Font.keeproll.body).foregroundStyle(Color.keeproll.inkPrimary)
            Spacer()
            value.font(Font.keeproll.caption).foregroundStyle(Color.keeproll.inkSecondary).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private func label(for state: PermissionState) -> LocalizedStringResource {
        switch state {
        case .authorized: "Allowed"
        case .limited: "Limited to selected photos"
        case .notDetermined: "Not asked yet"
        case .denied: "Not allowed"
        case .restricted: "Restricted on this iPhone"
        }
    }

    private func color(for state: PermissionState) -> Color {
        switch state {
        case .authorized: Color.keeproll.success
        case .limited, .notDetermined: Color.keeproll.warning
        case .denied, .restricted: Color.keeproll.inkSecondary
        }
    }
}


