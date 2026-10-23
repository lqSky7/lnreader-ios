// LibraryBadgeViews.swift - Badge toggles and the badge stacks on library cells

import SwiftData
import SwiftUI

/// The Settings toggles, readable from any cell. `general.showUnreadBadges`
/// predates the others and keeps its key.
struct LibraryBadgePrefs: DynamicProperty {
    @AppStorage("general.showUnreadBadges") private var unread = true
    @AppStorage("general.showDownloadBadges") private var downloaded = false
    @AppStorage("general.showLanguageBadges") private var language = false
    @AppStorage("general.showNewBadges") private var new = false

    var settings: LibraryBadgeSettings {
        LibraryBadgeSettings(unread: unread, downloaded: downloaded, language: language, new: new)
    }

    /// What a cell loads for its counts, so the extra queries only run when shown.
    var extras: LibraryChapterCounts.Extras { new ? .newCount : [] }
}

/// What a cell loads its counts for: the entry, and whether `new` is shown.
struct LibraryCountsTaskID: Hashable {
    let id: PersistentIdentifier
    let extras: Int
}

/// A compact capsule: an optional symbol, then text.
struct TextBadge: View {
    let text: String
    var systemImage: String?
    var style: BadgeView.BadgeStyle = .accent

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(text)
        }
        .font(Typography.small)
        .fontWeight(.bold)
        .foregroundStyle(AppTheme.onPrimaryFill)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(style.color, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// Badges laid over a cover: reading state at the top right, where the unread
/// count always sat, and library facts at the top left.
struct LibraryCoverBadges: View {
    let badges: LibraryBadges

    var body: some View {
        ZStack {
            VStack(alignment: .trailing, spacing: 4) {
                if badges.unread > 0 { BadgeView(count: badges.unread) }
                if badges.new > 0 {
                    TextBadge(text: "\(badges.new) new", systemImage: "sparkles", style: .secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            VStack(alignment: .leading, spacing: 4) {
                if badges.downloaded > 0 {
                    TextBadge(text: "\(badges.downloaded)", systemImage: "arrow.down", style: .secondary)
                }
                if let language = badges.language {
                    TextBadge(text: language, style: .secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(6)
        .allowsHitTesting(false)
    }
}
