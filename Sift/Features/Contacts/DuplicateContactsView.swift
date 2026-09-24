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
        .background(Color.sift.canvas)
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
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("^[\(vm.groups.count) group](inflect: true)")
                        .font(Font.sift.heroNumber)
                        .foregroundStyle(Color.sift.inkPrimary)
                        .contentTransition(.numericText())
                    Text("^[\(vm.duplicateCount) contact](inflect: true) that look like the same people")
                        .font(Font.sift.caption)
                        .foregroundStyle(Color.sift.inkSecondary)
                }
                Spacer()
                if vm.queuedMerges + vm.queuedDeletes > 0 {
                    Text("\(vm.queuedMerges) merges · \(vm.queuedDeletes) deletes")
                        .font(Font.sift.caption.weight(.semibold))
                        .foregroundStyle(Color.sift.accent)
                        .padding(.horizontal, Spacing.s).padding(.vertical, Spacing.xxs)
                        .background(Color.sift.accentSoft, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            InlineBanner(style: .info, systemImage: "externaldrive.badge.checkmark",
                         message: Text("Merging keeps every number and email. Sift saves a backup of the contacts before it changes anything."))
        }
        .padding(.top, Spacing.s)
        .animation(Motion.standard, value: vm.queuedMerges + vm.queuedDeletes)
    }

    private var locked: some View {
        EmptyState(systemImage: "lock", title: Text("Contacts access needed"),
                   message: Text("Sift checks contacts on this iPhone for duplicates. Nothing is uploaded.")) {
            PrimaryButton(title: vm.permission == .notDetermined ? "Allow access" : "Open Settings") {
                Task { await vm.requestAccess() }
            }
            .padding(.top, Spacing.s)
        }
        .padding(.top, Spacing.xxxl)
    }
}
