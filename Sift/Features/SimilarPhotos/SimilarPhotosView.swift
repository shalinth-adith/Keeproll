import SwiftUI

struct SimilarPhotosView: View {
    @State private var vm: SimilarPhotosViewModel

    init(env: AppEnvironment) {
        _vm = State(initialValue: SimilarPhotosViewModel(scanStore: env.scanStore, cart: env.cart, router: env.router))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.l) {
                header
                if vm.groups.isEmpty && !vm.isLoading && !vm.isScanning {
                    EmptyState(systemImage: "square.on.square",
                               title: Text("No similar photos"),
                               message: Text("Sift didn't find duplicates or near-identical shots."))
                } else {
                    ForEach(vm.groups) { group in
                        groupSection(group)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
            .animation(Motion.standard, value: vm.groups.map(\.id))
        }
        .background(Color.sift.canvas)
        .navigationTitle("Similar Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(vm.smartSelectActive ? "Clear" : "Smart select", systemImage: "sparkles") { vm.toggleSmartSelect() }
                    .disabled(vm.groups.isEmpty)
            }
        }
        .overlay {
            if vm.isLoading { ProgressView("Looking for similar photos…") }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(ByteFormatter.string(vm.freeableBytes))
                        .font(Font.sift.heroNumber)
                        .foregroundStyle(Color.sift.inkPrimary)
                        .contentTransition(.numericText())
                    Text("^[\(vm.groups.count) group](inflect: true) · ^[\(vm.photoCount) photo](inflect: true)")
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
            if vm.isScanning {
                HStack(spacing: Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Still scanning — groups appear as they're found")
                        .font(Font.sift.caption)
                        .foregroundStyle(Color.sift.inkSecondary)
                }
            }
            InlineBanner(style: .info, systemImage: "star",
                         message: Text("We picked the sharpest shot in each group as Best. Tap a photo to compare, or tap and hold to make it Best."))
        }
        .padding(.top, Spacing.s)
        .animation(Motion.standard, value: vm.selectedCount)
        .animation(Motion.standard, value: vm.freeableBytes)
    }

    private func groupSection(_ group: SimilarGroup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            GroupHeader(group: group, allOthersSelected: vm.allOthersSelected(in: group)) {
                vm.toggleOthers(in: group)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(group.members) { item in
                        cell(item, in: group)
                    }
                }
            }
        }
        .padding(Spacing.m)
        .background(Color.sift.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.sift.hairline))
    }

    private func cell(_ item: MediaItem, in group: SimilarGroup) -> some View {
        let isBest = item.id == group.bestID
        let selected = vm.isSelected(item)
        return ThumbnailView(id: item.id, pointSize: 150)
            .frame(width: 132, height: 132)
            .overlay {
                if selected {
                    Color.sift.accent.opacity(0.18)
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Color.sift.accent, lineWidth: 3)
                }
            }
            .overlay(alignment: .topLeading) {
                if isBest { BestBadge().padding(6) }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if item.isCloudOnly { CloudBadge() }
                    Text(ByteFormatter.string(item.byteSize ?? 0))
                        .font(Font.sift.badge)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                .padding(6)
            }
            .overlay(alignment: .topTrailing) {
                Button { vm.toggle(item) } label: {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(selected ? Color.sift.onAccent : .white, selected ? Color.sift.accent : .black.opacity(0.25))
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .symbolEffect(.bounce, value: selected)
                        .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(selected ? "Deselect" : "Select"))
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .onTapGesture { vm.openCompare(item, in: group) }
            .contextMenu {
                if !isBest { Button("Make Best", systemImage: "star") { vm.makeBest(item, in: group) } }
                Button(selected ? "Deselect" : "Select", systemImage: "checkmark.circle") { vm.toggle(item) }
                Button("Compare", systemImage: "rectangle.on.rectangle") { vm.openCompare(item, in: group) }
            }
            .sensoryFeedback(.selection, trigger: selected)
            .animation(Motion.standard, value: selected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Photo, \(ByteFormatter.string(item.byteSize ?? 0))\(isBest ? ", best in group" : "")\(selected ? ", selected" : "")"))
            .accessibilityAddTraits(.isButton)
    }
}
