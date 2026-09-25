import SwiftUI

struct DuplicateContactsView: View {
    @State private var vm: DuplicateContactsViewModel

    init(env: AppEnvironment) {
        _vm = State(initialValue: DuplicateContactsViewModel(scanStore: env.scanStore, cart: env.cart))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.m) {
                if !vm.permission.canRead {
                    locked
                } else {
                    header
                    if vm.groups.isEmpty && !vm.isLoading {
                        EmptyState(systemImage: "person.2", title: Text("No duplicates"),
                                   message: Text("Every contact looks unique."))
                    } else {
                        ForEach(vm.groups) { group in
                            ContactGroupCard(
                                group: group,
                                primaryID: vm.primaryID(for: group),
                                selectedForDeletion: vm.selectedForDeletion(in: group),
                                mergeQueued: vm.mergeQueued(for: group),
                                onSetPrimary: { vm.setPrimary($0, for: group) },
                                onToggleDelete: { vm.toggleDelete($0, in: group) },
                                onToggleMerge: { vm.toggleMerge(for: group) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.keeproll.canvas)
        .navigationTitle("Duplicate Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Merge all", systemImage: "arrow.triangle.merge") { vm.mergeAll() }
                    .disabled(vm.groups.isEmpty)
            }
        }
        .overlay { if vm.isLoading && vm.groups.isEmpty { ProgressView() } }
    }

    private var header: some View {
        CategoryHeader(
            hero: Text("^[\(vm.groups.count) group](inflect: true)"),
            caption: Text("^[\(vm.duplicateCount) contact](inflect: true) that look like the same people"),
            selectedCount: vm.queuedMerges + vm.queuedDeletes,
            hint: HintRow("externaldrive.badge.checkmark", Text("Merging keeps every number and email. A backup is saved before anything changes."))
        )
    }

    private var locked: some View {
        EmptyState(systemImage: "lock", title: Text("Contacts access needed"),
                   message: Text("Keeproll checks contacts on this iPhone for duplicates. Nothing is uploaded.")) {
            PrimaryButton(title: vm.permission == .notDetermined ? "Allow access" : "Open Settings") {
                Task { await vm.requestAccess() }
            }
            .padding(.top, Spacing.s)
        }
        .padding(.top, Spacing.xxxl)
    }
}
