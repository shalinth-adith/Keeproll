import AVKit
import SwiftUI

struct LargeVideosView: View {
    @State private var vm: LargeVideosViewModel

    init(env: AppEnvironment) {
        _vm = State(initialValue: LargeVideosViewModel(scanStore: env.scanStore, cart: env.cart, router: env.router))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s) {
                header
                FilterChips(options: LargeVideosViewModel.Filter.allCases, selection: $vm.filter) { filter in
                    switch filter {
                    case .all: Text("All")
                    case .over100MB: Text("Over 100 MB")
                    case .over500MB: Text("Over 500 MB")
                    }
                }
                .padding(.horizontal, -Spacing.m)
                .padding(.bottom, Spacing.xs)

                if vm.items.isEmpty && !vm.isLoading {
                    EmptyState(systemImage: "video",
                               title: Text("No large videos"),
                               message: Text(vm.filter == .all ? "You have no videos." : "No videos match this size."))
                } else {
                    ForEach(vm.items) { item in
                        VideoRow(item: item, isSelected: vm.isSelected(item), onToggle: { vm.toggle(item) }, onPreview: { vm.preview(item) })
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.sift.canvas)
        .navigationTitle("Large Videos")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if vm.isLoading && vm.items.isEmpty { ProgressView() } }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(ByteFormatter.string(vm.totalBytes))
                    .font(Font.sift.heroNumber)
                    .foregroundStyle(Color.sift.inkPrimary)
                    .contentTransition(.numericText())
                Text("^[\(vm.items.count) video](inflect: true) · largest first")
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
        .padding(.top, Spacing.s)
        .animation(Motion.standard, value: vm.totalBytes)
        .animation(Motion.standard, value: vm.selectedCount)
    }
}

/// Inline player sheet (FR-VID-2).
struct VideoPreviewView: View {
    let id: String
    let playback: VideoPlaybackProviding
    @State private var player: AVPlayer?
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                } else if failed {
                    EmptyState(systemImage: "icloud.slash", title: Text("Can't play this video"),
                               message: Text("It may still be downloading from iCloud."))
                        .foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            if let item = await playback.playerItem(for: id) {
                player = AVPlayer(playerItem: item)
            } else {
                failed = true
            }
        }
        .onDisappear { player?.pause() }
    }
}
