import SwiftUI

// MARK: - QueueView

/// The upcoming play queue. Reuses `SongRow` for each entry and highlights
/// the currently playing track.
struct QueueView: View {
    @Environment(PlayerService.self) private var playerService
    @Environment(\.dismiss) private var dismiss

    @State private var showingClearConfirmation = false
    @State private var showingSaveQueuePrompt = false
    @State private var playlistTitle = ""
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            List {
                if self.playerService.queueEntries.isEmpty {
                    Section {
                        EmptyStateView(
                            title: "Queue is Empty",
                            message: "Play something to build a queue.",
                            systemImage: "list.bullet"
                        )
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    if let currentItem = self.currentQueueItem {
                        Section("Current") {
                            QueueRow(
                                song: currentItem.entry.song,
                                isCurrent: true
                            ) {
                                Task { await self.playerService.playFromQueue(at: currentItem.index) }
                                HapticService.playback()
                            }
                            .moveDisabled(true)
                            .deleteDisabled(true)
                        }
                    }

                    if !self.addedQueueItems.isEmpty {
                        Section("Added by You") {
                            ForEach(self.addedQueueItems) { item in
                                QueueRow(
                                    song: item.entry.song,
                                    isCurrent: false
                                ) {
                                    Task { await self.playerService.playFromQueue(at: item.index) }
                                    HapticService.playback()
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        self.playerService.removeFromQueue(at: item.index)
                                        HapticService.toggle()
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                            .onMove { source, destination in
                                self.playerService.reorderQueue(
                                    inGroupWith: self.addedQueueItems.map(\.entry.id),
                                    from: source,
                                    to: destination
                                )
                            }
                        }
                    }

                    if !self.radioQueueItems.isEmpty {
                        Section("Radio") {
                            ForEach(self.radioQueueItems) { item in
                                QueueRow(
                                    song: item.entry.song,
                                    isCurrent: false
                                ) {
                                    Task { await self.playerService.playFromQueue(at: item.index) }
                                    HapticService.playback()
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        self.playerService.removeFromQueue(at: item.index)
                                        HapticService.toggle()
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                            .onMove { source, destination in
                                self.playerService.reorderQueue(
                                    inGroupWith: self.radioQueueItems.map(\.entry.id),
                                    from: source,
                                    to: destination
                                )
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !self.playerService.queueEntries.isEmpty {
                        EditButton()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            self.playlistTitle = self.defaultPlaylistTitle
                            self.showingSaveQueuePrompt = true
                        } label: {
                            Label("Save as Playlist", systemImage: "text.badge.plus")
                        }
                        .disabled(self.playerService.queueEntries.isEmpty)

                        Button(role: .destructive) {
                            self.showingClearConfirmation = true
                        } label: {
                            Label("Clear Queue", systemImage: "trash")
                        }
                        .disabled(self.playerService.queueEntries.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { self.dismiss() }
                }
            }
            .alert("Clear Queue?", isPresented: self.$showingClearConfirmation) {
                Button("Clear", role: .destructive) {
                    self.playerService.clearQueue()
                    HapticService.toggle()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This keeps the current song and removes the rest of Up Next.")
            }
            .alert("Save Queue", isPresented: self.$showingSaveQueuePrompt) {
                TextField("Playlist name", text: self.$playlistTitle)
                Button("Save") {
                    Task { await self.saveQueueAsPlaylist() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Unable to Save Queue",
                isPresented: Binding(
                    get: { self.saveError != nil },
                    set: { if !$0 { self.saveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(self.saveError ?? "")
            }
        }
    }

    private var defaultPlaylistTitle: String {
        "Kaset Queue"
    }

    private var queueItems: [QueueDisplayItem] {
        self.playerService.queueEntries.enumerated().map { index, entry in
            QueueDisplayItem(index: index, entry: entry)
        }
    }

    private var currentQueueItem: QueueDisplayItem? {
        self.queueItems.first(where: { $0.index == self.playerService.currentIndex })
    }

    private var addedQueueItems: [QueueDisplayItem] {
        self.queueItems.filter { item in
            item.index != self.playerService.currentIndex && item.entry.source != .radio
        }
    }

    private var radioQueueItems: [QueueDisplayItem] {
        self.queueItems.filter { item in
            item.index != self.playerService.currentIndex && item.entry.source == .radio
        }
    }

    private func saveQueueAsPlaylist() async {
        do {
            _ = try await self.playerService.saveQueueAsPlaylist(title: self.playlistTitle)
            HapticService.toggle()
        } catch {
            self.saveError = error.localizedDescription
        }
    }
}

private struct QueueDisplayItem: Identifiable {
    let index: Int
    let entry: QueueEntry

    var id: UUID {
        self.entry.id
    }
}

// MARK: - QueueRow

/// A single row in `QueueView`: an indicator column + the shared `SongRow`.
private struct QueueRow: View {
    let song: Song
    let isCurrent: Bool
    let playAction: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            Group {
                if self.isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                        .font(.caption)
                }
            }
            .frame(width: 16)

            SongRow(
                song: self.song,
                showsLikeButton: false,
                showsDuration: true,
                showsOverflowMenu: false,
                showsPlayNextSwipeAction: false,
                primaryAction: self.playAction
            )
        }
        .listRowBackground(self.isCurrent ? Theme.Colors.surfaceStrong : Color.clear)
    }
}
