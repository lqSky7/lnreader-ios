// HistoryRow.swift
// Single history entry showing the book, chapter, and time ago. When the same
// book was read several times in a row, the newest read heads the run and a
// count pill opens the earlier chapters beneath it as `HistoryChapterRow`s.

import SwiftUI

struct HistoryRow: View {
    let history: History
    /// Earlier reads of the same entry folded under this row; 0 shows no pill.
    var earlierCount = 0
    var isExpanded = false
    /// Tapping the cover opens the entry; tapping anywhere else opens the chapter.
    var onOpenEntry: () -> Void = {}
    var onOpenChapter: () -> Void = {}
    var onToggle: () -> Void = {}
    @Environment(SourceManager.self) private var sourceManager

    private var entry: Entry? { history.chapter?.entry }

    private var sourceName: String {
        guard let entry else { return "" }
        return sourceManager.source(forKey: entry.sourceKey)?.name
            ?? SourceKey.identifier(from: entry.sourceKey)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenEntry) {
                cover
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(entry?.displayTitle ?? "entry")")

            HStack(spacing: 12) {
                details
                Spacer()
                Text(history.lastRead.timeAgo)
                    .font(Typography.small)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenChapter)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the chapter")

            if earlierCount > 0 {
                RunToggle(count: earlierCount, isExpanded: isExpanded, action: onToggle)
            }
        }
        .padding(.vertical, 4)
    }

    /// A folded run shows its cover as a small stack, so the row reads as
    /// more than one read before the pill is noticed.
    private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        let stacked = earlierCount > 0 && !isExpanded
        return NovelCoverView(
            url: entry?.displayThumbnailURL,
            aspectRatio: LayoutConstants.coverAspectRatio
        )
        .frame(width: 44, height: 63)
        .clipShape(shape)
        .background(alignment: .top) {
            if stacked {
                shape
                    .fill(.quaternary)
                    .frame(width: 36, height: 63)
                    .offset(y: -4)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
                Text(entry?.displayTitle ?? "Unknown")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(history.chapter?.name ?? "")
                    .font(Typography.body)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(sourceName)
                        .font(Typography.small)
                        .foregroundStyle(.tertiary)

                    if let progress = history.chapter?.progress, progress > 0, progress < 100 {
                        Text("\(Int(progress))%")
                            .font(Typography.small)
                            .foregroundStyle(.secondary)
                    }
                }
            }
    }
}

/// The pill on a run's head row: how many earlier chapters it holds, and a
/// chevron that turns when they are showing.
private struct RunToggle: View {
    let count: Int
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("+\(count)")
                    .font(Typography.small.weight(.semibold))
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(Typography.small.weight(.bold))
                    .rotationEffect(.degrees(isExpanded ? -180 : 0))
            }
            .foregroundStyle(isExpanded ? AppTheme.onPrimaryFill : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isExpanded ? AnyShapeStyle(AppTheme.primaryFill) : AnyShapeStyle(.quaternary))
            )
            // The pill is small; the tap target is not.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Hide earlier chapters" : "Show \(count) earlier chapters")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

/// An earlier chapter inside an open run. The book is already named by the
/// head row, so this is the chapter, its progress and when, set in from the
/// cover column with a rail tying it to the head.
struct HistoryChapterRow: View {
    let history: History
    var onOpenChapter: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(.quaternary)
                .frame(width: 2)
                .frame(width: 44)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(history.chapter?.name ?? "")
                        .font(Typography.body)
                        .lineLimit(1)

                    if let progress = history.chapter?.progress, progress > 0, progress < 100 {
                        Text("\(Int(progress))%")
                            .font(Typography.small)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(history.lastRead.timeAgo)
                    .font(Typography.small)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenChapter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the chapter")
    }
}
