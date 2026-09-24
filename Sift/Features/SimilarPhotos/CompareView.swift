import SwiftUI

/// Full-screen pager through one similar group (FR-SIM-5).
struct CompareView: View {
    @State private var vm: SimilarPhotosViewModel
    let groupID: UUID
    @State private var currentID: String
    @Environment(\.dismiss) private var dismiss

    init(env: AppEnvironment, groupID: UUID, startID: String) {
        _vm = State(initialValue: SimilarPhotosViewModel(scanStore: env.scanStore, cart: env.cart, router: env.router))
        self.groupID = groupID
        _currentID = State(initialValue: startID)
    }

    private var group: SimilarGroup? { vm.group(id: groupID) }
    private var current: MediaItem? { group?.members.first { $0.id == currentID } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let group {
                TabView(selection: $currentID) {
                    ForEach(group.members) { item in
                        ThumbnailView(id: item.id, pointSize: 800, allowsNetwork: true)
                            .aspectRatio(CGFloat(max(item.pixelWidth, 1)) / CGFloat(max(item.pixelHeight, 1)), contentMode: .fit)
                            .tag(item.id)
                            .padding(.horizontal, Spacing.xs)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                EmptyState(systemImage: "square.on.square", title: Text("Group cleaned"), message: Text("These photos are no longer in the list."))
                    .foregroundStyle(.white)
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sensoryFeedback(.selection, trigger: currentID)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: Layout.minTouchTarget, height: Layout.minTouchTarget)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .accessibilityLabel(Text("Back"))
            Spacer()
            if let group, let current {
                VStack(spacing: 2) {
                    Text("\((group.members.firstIndex { $0.id == current.id } ?? 0) + 1) of \(group.members.count)")
                        .font(Font.sift.headline).foregroundStyle(.white)
                    Text("\(ByteFormatter.string(current.byteSize ?? 0)) · \(current.pixelWidth)×\(current.pixelHeight)")
                        .font(Font.sift.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            if let group, let current, current.id != group.bestID {
                Button { vm.makeBest(current, in: group) } label: {
                    Label("Make Best", systemImage: "star")
                        .font(Font.sift.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.s)
                        .frame(minHeight: Layout.minTouchTarget)
                        .background(.white.opacity(0.14), in: Capsule())
                }
            } else {
                BestBadge().frame(minHeight: Layout.minTouchTarget)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .background(.black.opacity(0.6))
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.s) {
            if let group {
                HStack(spacing: Spacing.xs) {
                    ForEach(group.members) { item in
                        ThumbnailView(id: item.id, pointSize: 60)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous)
                                .strokeBorder(item.id == currentID ? Color.sift.accent : .clear, lineWidth: 2))
                            .overlay(alignment: .topTrailing) {
                                if vm.isSelected(item) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Color.sift.onAccent, Color.sift.accent)
                                        .offset(x: 4, y: -4)
                                }
                            }
                            .opacity(item.id == currentID ? 1 : 0.6)
                            .onTapGesture { withAnimation(Motion.standard) { currentID = item.id } }
                    }
                }
            }
            if let current {
                let selected = vm.isSelected(current)
                Button { vm.toggle(current) } label: {
                    Label(selected ? "Selected to remove" : "Select to remove", systemImage: selected ? "checkmark.circle.fill" : "circle")
                        .font(Font.sift.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(selected ? Color.sift.onAccent : .white)
                        .background(selected ? Color.sift.accent : .white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .animation(Motion.standard, value: selected)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .background(.black.opacity(0.6))
    }
}
