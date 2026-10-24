// ChapterRow.swift
// Single chapter row with unread indicator, release time, and status icons.

import SwiftUI

struct ChapterRow: View {
    @Environment(ReaderRouter.self) private var readerRouter
    @Namespace private var chapterTransition
    @ObservedObject private var audioLibrary = TTSOfflineLibrary.shared
    @State private var showAudioDownloads = false
    /// A hold ends with a lift that the button also reads as a tap; without this
    /// the tap would toggle the row the hold just selected straight back off.
    @State private var suppressTap = false
    let chapter: ChapterDisplay
    let entry: Entry?
    let sourceKey: String
    /// Hold-to-select state shared with the list that owns this row. `nil`
    /// where selecting makes no sense (a browse result has no stored chapters).
    var selection: ChapterSelection? = nil
    /// The list's current order, read only when a long press needs a range.
    var orderedPaths: () -> [String] = { [] }
    private var isSelecting: Bool { selection?.isActive == true }
    private var isSelected: Bool { selection?.paths.contains(chapter.path) == true }
    private var bookPath: String { entry?.url ?? chapter.entryURL ?? chapter.path }
    private var bookID: String { TTSBookIdentity.make(pluginId: sourceKey, novelPath: bookPath) }
    private var audioCount: Int { audioLibrary.downloads(bookId: bookID, chapterId: chapter.path).filter(\.isAvailable).count }

    /// The unread dot, or the selection circle while picking. One fixed slot, so
    /// entering selection mode does not shift the title.
    private var leadingIndicator: some View {
        Group {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            } else {
                Circle()
                    .fill(chapter.unread ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 22)
        .accessibilityHidden(true)
    }

    var body: some View {
        Button {
            if suppressTap {
                suppressTap = false
                return
            }
            if let selection, selection.isActive {
                selection.toggle(chapter.path)
                return
            }
            readerRouter.open(
                chapter,
                sourceKey: sourceKey,
                entryURL: entry?.url ?? chapter.entryURL,
                kind: entry?.kind ?? chapter.kind
            )
        } label: {
            HStack(spacing: 12) {
                leadingIndicator

                VStack(alignment: .leading, spacing: 4) {
                    Text(chapter.name)
                        .font(Typography.body)
                        .foregroundStyle(chapter.unread ? .primary : .secondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let scanlator = chapter.scanlator, !scanlator.isEmpty {
                            Text(scanlator.prefix(1).uppercased() + scanlator.dropFirst())
                                .font(Typography.small)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        if let releaseTime = chapter.releaseTime {
                            Text(releaseTime)
                                .font(Typography.small)
                                .foregroundStyle(.tertiary)
                        }

                        if chapter.unread, let progress = chapter.progress, progress > 0, progress < 100 {
                            Text("\(progress)%")
                                .font(Typography.small)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Status icons
                HStack(spacing: 8) {
                    if audioCount > 0 {
                        Label("\(audioCount)", systemImage: "headphones").font(Typography.small).foregroundStyle(.secondary)
                            .accessibilityLabel("\(audioCount) voices available offline")
                    }
                    if chapter.bookmarked {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.primary)
                            .font(Typography.caption)
                    }
                    if chapter.downloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(Typography.caption)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.clear))
            .bookTransitionSource(chapter.path, in: chapterTransition)
        }
        .buttonStyle(.plain)
        // Hold to start selecting; hold another row while selecting to take
        // everything between. Per-chapter actions (download, audio) live in the
        // selection bar, so there is no context menu competing for the hold.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                guard let selection else { return }
                Haptics.shared.impact(.medium)
                suppressTap = true
                // The lift may not report a tap at all; don't eat the next real one.
                Task { try? await Task.sleep(for: .milliseconds(600)); suppressTap = false }
                if selection.isActive {
                    selection.extend(to: chapter.path, in: orderedPaths())
                } else {
                    selection.begin(chapter.path)
                }
            }
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(chapter.unread ? "Unread" : "Read")
    }
}

// MARK: - Selection

/// Which chapters are picked in a chapter list. Owned by the screen that shows
/// the list so its action bar can pin to the screen rather than scroll away.
@Observable
final class ChapterSelection {
    private(set) var isActive = false
    private(set) var paths: Set<String> = []
    /// The row selection grows from: the last one tapped or held.
    private(set) var anchor: String?

    func begin(_ path: String) {
        isActive = true
        paths = [path]
        anchor = path
    }

    func toggle(_ path: String) {
        if paths.contains(path) { paths.remove(path) } else { paths.insert(path); anchor = path }
    }

    /// Add every chapter between the anchor and `path`, inclusive.
    func extend(to path: String, in order: [String]) {
        guard let from = anchor.flatMap({ order.firstIndex(of: $0) }),
              let to = order.firstIndex(of: path) else { paths.insert(path); anchor = path; return }
        paths.formUnion(order[min(from, to)...max(from, to)])
        anchor = path
    }

    /// Everything from the anchor (or the first pick) down to the end of the list.
    func selectBelow(in order: [String]) {
        let start = anchor.flatMap { order.firstIndex(of: $0) }
            ?? order.firstIndex(where: paths.contains) ?? 0
        paths.formUnion(order[start...])
    }

    func selectAll(in order: [String]) { paths = Set(order) }

    func invert(in order: [String]) { paths = Set(order).subtracting(paths) }

    func end() { isActive = false; paths = []; anchor = nil }
}

/// Selection actions as a system bottom bar: read state, download and a menu for
/// the rest. Apply with `chapterSelectionToolbar`, so the host's own bottom items
/// stay untouched while nothing is selected.
struct ChapterSelectionToolbar: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(TrackingManager.self) private var tracking
    let selection: ChapterSelection
    let entry: Entry?
    /// The list the selection was made in, in display order.
    let ordered: [ChapterDisplay]
    /// Every chapter of the book, for "mark previous as read".
    let allChapters: [ChapterDisplay]
    let sourceKey: String
    @State private var showAudio = false

    private var picked: [Chapter] {
        entry?.chapters.filter { selection.paths.contains($0.url) } ?? []
    }
    private var orderedPaths: [String] { ordered.map(\.path) }
    private var canDownload: Bool { entry?.isLocal == false }
    private var bookPath: String { entry?.url ?? "" }

    func body(content: Content) -> some View {
        content
            .toolbar { if selection.isActive { selectionItems } }
            .toolbar(selection.isActive ? .visible : .automatic, for: .bottomBar)
            .toolbarVisibility(selection.isActive ? .hidden : .automatic, for: .tabBar)
            .sheet(isPresented: $showAudio) { audioSheet }
    }

    @ToolbarContentBuilder private var selectionItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { selection.end() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                    Text("\(selection.paths.count)").monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("Cancel selection")
            .accessibilityValue("\(selection.paths.count) selected")
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button { setRead(true) } label: { Label("Mark as read", systemImage: "eye") }
            Button { setRead(false) } label: { Label("Mark as unread", systemImage: "eye.slash") }
            if canDownload {
                Button { download() } label: { Label("Download", systemImage: "arrow.down.circle") }
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) { moreMenu }
    }

    private var moreMenu: some View {
        Menu {
            Button("Select all below", systemImage: "arrow.down.to.line") { selection.selectBelow(in: orderedPaths) }
            Button("Select all", systemImage: "checklist") { selection.selectAll(in: orderedPaths) }
            Button("Invert selection", systemImage: "arrow.left.arrow.right") { selection.invert(in: orderedPaths) }
            Divider()
            Button("Mark previous as read", systemImage: "eye") { markPreviousRead() }
            Button(allBookmarked ? "Remove bookmark" : "Bookmark", systemImage: "bookmark") { toggleBookmark() }
            if selection.paths.count == 1, (entry?.kind ?? .novel) == .novel {
                Button("Chapter audio", systemImage: "headphones") { showAudio = true }
            }
            if canDownload {
                Divider()
                Button("Delete download", systemImage: "trash", role: .destructive) { deleteDownloads() }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    @ViewBuilder private var audioSheet: some View {
        if let chapter = ordered.first(where: { selection.paths.contains($0.path) }) {
            BookAudioDownloadsView(
                bookId: TTSBookIdentity.make(pluginId: sourceKey, novelPath: bookPath),
                bookTitle: entry?.displayTitle ?? chapter.name, sourceKey: sourceKey, entryURL: bookPath,
                chapters: [TTSChapterChoice(chapter)], coverURL: entry?.displayThumbnailURL, initialChapter: chapter.path)
        }
    }

    private var allBookmarked: Bool { !picked.isEmpty && picked.allSatisfy(\.bookmark) }

    // MARK: Actions

    private func finish() {
        try? modelContext.save()
        if let entry { tracking.readStateChanged(entry: entry) }
        LibraryChapterCounts.shared.invalidate()
        selection.end()
    }

    private func setRead(_ read: Bool) {
        for chapter in picked { apply(read: read, to: chapter) }
        finish()
    }

    private func apply(read: Bool, to chapter: Chapter) {
        guard chapter.read != read || chapter.progress != (read ? 100 : 0) else { return }
        chapter.read = read
        chapter.progress = read ? 100 : 0
        chapter.paragraphIndex = read ? 0 : nil
        chapter.lastPageRead = 0
        chapter.pagesLeft = 0
    }

    /// Every chapter numbered below the lowest one picked.
    private func markPreviousRead() {
        guard let floor = allChapters.filter({ selection.paths.contains($0.path) }).map(\.sortNumber).min() else { return }
        let earlier = Set(allChapters.filter { $0.sortNumber < floor }.map(\.path))
        for chapter in entry?.chapters ?? [] where earlier.contains(chapter.url) { apply(read: true, to: chapter) }
        finish()
    }

    private func toggleBookmark() {
        let target = !allBookmarked
        for chapter in picked { chapter.bookmark = target }
        finish()
    }

    private func download() {
        ChapterDownloadManager.shared.enqueue(picked.filter { !$0.isDownloaded })
        selection.end()
    }

    private func deleteDownloads() {
        for item in picked.compactMap(\.downloadItem) { ChapterDownloadManager.shared.remove(item) }
        selection.end()
    }
}

extension View {
    func chapterSelectionToolbar(
        selection: ChapterSelection, entry: Entry?, ordered: [ChapterDisplay],
        allChapters: [ChapterDisplay], sourceKey: String
    ) -> some View {
        modifier(ChapterSelectionToolbar(
            selection: selection, entry: entry, ordered: ordered,
            allChapters: allChapters, sourceKey: sourceKey))
    }
}
