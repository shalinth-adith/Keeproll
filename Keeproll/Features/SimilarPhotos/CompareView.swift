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
                        .font(Font.keeproll.headline).foregroundStyle(.white)
                    Text("\(ByteFormatter.string(current.byteSize ?? 0)) · \(current.pixelWidth)×\(current.pixelHeight)")
                        .font(Font.keeproll.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            if let group, let current, current.id != group.bestID {
                Button { vm.makeBest(current, in: group) } label: {
                    Label("Make Best", systemImage: "star")
                        .font(Font.keeproll.caption.weight(.semibold))
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
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.6))
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.s) {
            if let group {
                // A scrolling strip: a fixed row of 48 pt thumbnails is wider than the
                // screen for big groups and pushed the Back button off-screen (QA H1).
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: Spacing.xs) {
                            ForEach(group.members) { item in
                                stripThumbnail(item)
                                    .id(item.id)
                            }
                        }
                        .padding(.vertical, Spacing.xxs)
                        .padding(.horizontal, Spacing.xxs)
                    }
                    .frame(height: 60)
                    .onAppear { proxy.scrollTo(currentID, anchor: .center) }
                    .onChange(of: currentID) { _, id in
                        withAnimation(Motion.standard) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            if let current {
                let selected = vm.isSelected(current)
                Button { vm.toggle(current) } label: {
                    Label(selected ? "Selected to remove" : "Select to remove", systemImage: selected ? "checkmark.circle.fill" : "circle")
                        .font(Font.keeproll.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(selected ? Color.keeproll.onAccent : .white)
                        .background(selected ? Color.keeproll.accent : .white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .animation(Motion.standard, value: selected)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.6))
    }

    private func stripThumbnail(_ item: MediaItem) -> some View {
        ThumbnailView(id: item.id, pointSize: 60)
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous)
                .strokeBorder(item.id == currentID ? Color.keeproll.accent : .clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if vm.isSelected(item) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.keeproll.onAccent, Color.keeproll.accent)
                        .offset(x: 4, y: -4)
                }
            }
            .opacity(item.id == currentID ? 1 : 0.6)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Motion.standard) { currentID = item.id } }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(item.id == currentID ? "Current photo" : "Show this photo"))
    }
}
