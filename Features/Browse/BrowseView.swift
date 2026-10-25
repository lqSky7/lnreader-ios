// BrowseView.swift
// Sources, split by kind: light novels and manga are separate catalogues.
//
// Every source is built into the app, so each catalogue is just the registry filtered by kind.
// A native segmented control in a glass top bar switches between them in place.

import SwiftUI

/// Which catalogue the browse screen is showing.
enum BrowseKind: String, CaseIterable, Identifiable {
    case novels
    case manga

    var id: String { rawValue }

    var title: String {
        switch self {
        case .novels: "Light Novels"
        case .manga: "Manga"
        }
    }

    var contentKind: ContentKind {
        switch self {
        case .novels: .novel
        case .manga: .manga
        }
    }
}

struct BrowseView: View {
    @Environment(SourceManager.self) private var sourceManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("browse.kind") private var kindRaw = BrowseKind.novels.rawValue
    @State private var searchText = ""

    private var kind: BrowseKind {
        BrowseKind(rawValue: kindRaw) ?? .novels
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Browse")
                .navigationBarTitleDisplayMode(.large)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: searchPrompt
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .toolbar { toolbarContent }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if kind == .novels {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    GlobalSearchView()
                } label: {
                    Image(systemName: "text.magnifyingglass")
                }
                .accessibilityLabel("Search all sources")
            }
        }
    }

    // MARK: - Kind switcher

    /// Native segmented control: on iOS 26 it renders as glass and morphs the
    /// selection for free. It floats in the top bar so the list scrolls under it.
    private var kindSwitcher: some View {
        Picker("Catalogue", selection: $kindRaw) {
            ForEach(BrowseKind.allCases) { option in
                Text(option.title).tag(option.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .hapticFeedback(.selection, trigger: kindRaw)
    }

    private var searchPrompt: String {
        kind == .novels ? "Search novel sources" : "Search manga sources"
    }

    // MARK: - Content

    /// One list for both catalogues. The switcher is its first row, so it scrolls
    /// away with the content instead of pinning over the navigation bar's search
    /// field, and switching kinds cross-fades rows in place: no second scroll view, no
    /// whole-page transition to lag behind the gesture.
    private var content: some View {
        List {
            Section {
                kindSwitcher
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            sourcesContent
        }
        // Rows cross-fade in place. Animating the rows, not the list, keeps the
        // scroll view (and the nav bar tracking it) alive, so it stays cheap.
        .animation(AppMotion.tabSwitch(reduceMotion: reduceMotion), value: kindRaw)
        .simultaneousGesture(kindSwipe)
    }

    /// Steps between catalogues on a clearly horizontal swipe. Only reacts when
    /// the drag ends, so vertical scrolling is never touched.
    private var kindSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 80, abs(dx) > abs(value.translation.height) * 2 else { return }
                let target: BrowseKind = dx < 0 ? .manga : .novels
                if target != kind { kindRaw = target.rawValue }
            }
    }

    @ViewBuilder
    private var sourcesContent: some View {
        if visibleSources.isEmpty {
            Section {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        kind == .novels ? "No novel sources" : "No manga sources",
                        systemImage: "books.vertical"
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .listRowBackground(Color.clear)
        } else {
            Section("Sources · \(visibleSources.count)") {
                ForEach(visibleSources, id: \.key) { source in
                    NavigationLink {
                        SourceDetailView(sourceKey: source.key, title: source.name)
                    } label: {
                        sourceRow(source)
                    }
                }
            }
        }
    }

    private func sourceRow(_ source: any CatalogSource) -> some View {
        HStack(spacing: 12) {
            SourceIconView(source: source, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(sourceSubtitle(source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func sourceSubtitle(_ source: any CatalogSource) -> String {
        var parts: [String] = []
        if !source.lang.isEmpty { parts.append(source.lang.uppercased()) }
        if !source.supportsLatest { parts.append("Popular only") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Filtering

    private var visibleSources: [any CatalogSource] {
        let all = sourceManager.sources(of: kind.contentKind)
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}
