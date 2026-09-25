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
                        VideoRow(item: item, isSelected: vm.isSelected(item), onToggle: { vm.toggle(item) }, onPreview: { vm.preview(item) },
                                 compressSaving: vm.compressSaving(for: item), onCompress: { vm.compress(item) })
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.keeproll.canvas)
        .navigationTitle("Large Videos")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if vm.isLoading && vm.items.isEmpty { ProgressView() } }
    }

    private var header: some View {
        CategoryHeader(
            hero: Text(ByteFormatter.string(vm.totalBytes)),
            caption: Text("^[\(vm.items.count) video](inflect: true) · largest first"),
            selectedCount: vm.selectedCount,
            hint: HintRow("play.circle", Text("Tap a thumbnail to watch before you decide."))
        )
        .animation(Motion.standard, value: vm.totalBytes)
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
