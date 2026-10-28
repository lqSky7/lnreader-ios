// SourceFilters.swift - Browse filters, mirroring Mihon's Filter model.

import Foundation

// MARK: - Option

/// One selectable choice inside a filter.
struct FilterOption: Identifiable, Hashable, Sendable, Codable {
    /// Value the source expects back.
    let id: String
    let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Definition

/// A filter a source exposes on its browse screen.
///
/// Definitions only: the values the user picks live in `FilterState`, so a
/// SwiftUI form can bind to them and a request can be built from them without
/// mutating the source. This is the one place v2 deviates from the plan's
/// `search(query:page:filters: [SourceFilter])` signature, which assumed
/// stateful filter objects.
enum SourceFilter: Identifiable, Hashable, Sendable, Codable {

    /// Section label, no value.
    case header(id: String, name: String)
    /// Visual divider, no value.
    case separator(id: String)

    /// Single choice.
    case select(id: String, name: String, options: [FilterOption], defaultOption: String?)
    /// Free text.
    case text(id: String, name: String, hint: String?, defaultValue: String)
    /// On / off.
    case checkbox(id: String, name: String, defaultValue: Bool)
    /// Include / exclude a single value.
    case triState(id: String, name: String)
    /// Multiple choice (LN plugins' `checkboxGroup`).
    case multiSelect(
        id: String, name: String, options: [FilterOption], defaultSelection: [String]
    )
    /// Include / exclude per value (LN plugins' `excludableCheckboxGroup`).
    case excludable(
        id: String,
        name: String,
        options: [FilterOption],
        defaultIncluded: [String],
        defaultExcluded: [String]
    )
    /// Sort field plus direction.
    case sort(
        id: String, name: String, options: [FilterOption], defaultIndex: Int, defaultAscending: Bool
    )
    /// Nested filters, rendered as a section.
    case group(id: String, name: String, children: [SourceFilter])

    var id: String {
        switch self {
        case .header(let id, _),
            .separator(let id),
            .select(let id, _, _, _),
            .text(let id, _, _, _),
            .checkbox(let id, _, _),
            .triState(let id, _),
            .multiSelect(let id, _, _, _),
            .excludable(let id, _, _, _, _),
            .sort(let id, _, _, _, _),
            .group(let id, _, _):
            return id
        }
    }

    var name: String? {
        switch self {
        case .header(_, let name),
            .select(_, let name, _, _),
            .text(_, let name, _, _),
            .checkbox(_, let name, _),
            .triState(_, let name),
            .multiSelect(_, let name, _, _),
            .excludable(_, let name, _, _, _),
            .sort(_, let name, _, _, _),
            .group(_, let name, _):
            return name
        case .separator:
            return nil
        }
    }

    /// Whether this case carries a value the user can change.
    var isSelectable: Bool {
        switch self {
        case .header, .separator: false
        default: true
        }
    }

    /// Leaf filters, flattening groups.
    static func flatten(_ filters: [SourceFilter]) -> [SourceFilter] {
        filters.flatMap { filter -> [SourceFilter] in
            if case .group(_, _, let children) = filter {
                return flatten(children)
            }
            return [filter]
        }
    }
}

// MARK: - Selection

/// The value the user picked for one filter.
enum FilterSelection: Hashable, Sendable {
    case text(String)
    case option(String)
    case checkbox(Bool)
    case triState(included: Bool, excluded: Bool)
    case options(Set<String>)
    case exclude(included: Set<String>, excluded: Set<String>)
    case sort(index: Int, ascending: Bool)
}

/// Values for every filter of one browse screen.
struct FilterState: Hashable, Sendable {

    private var values: [String: FilterSelection]

    init(values: [String: FilterSelection] = [:]) {
        self.values = values
    }

    subscript(id: String) -> FilterSelection? {
        get { values[id] }
        set { values[id] = newValue }
    }

    /// Value for `filter`, falling back to the filter's own default.
    func value(for filter: SourceFilter) -> FilterSelection? {
        if let selected = values[filter.id] { return selected }

        switch filter {
        case .text(_, _, _, let defaultValue):
            return .text(defaultValue)
        case .select(_, _, _, let defaultOption):
            return defaultOption.map { .option($0) }
        case .checkbox(_, _, let defaultValue):
            return .checkbox(defaultValue)
        case .triState:
            return .triState(included: false, excluded: false)
        case .multiSelect(_, _, _, let defaultSelection):
            return .options(Set(defaultSelection))
        case .excludable(_, _, _, let included, let excluded):
            return .exclude(included: Set(included), excluded: Set(excluded))
        case .sort(_, _, _, let index, let ascending):
            return .sort(index: index, ascending: ascending)
        case .header, .separator, .group:
            return nil
        }
    }

    /// State pre-filled with every filter's default, for a fresh browse screen.
    static func defaults(for filters: [SourceFilter]) -> FilterState {
        var state = FilterState()
        for filter in SourceFilter.flatten(filters) {
            state.values[filter.id] = state.value(for: filter)
        }
        return state
    }

    /// Number of leaf filters whose value differs from the filter's default.
    func modifiedCount(for filters: [SourceFilter]) -> Int {
        SourceFilter.flatten(filters).filter { filter in
            guard filter.isSelectable, let raw = values[filter.id] else { return false }
            return raw != FilterState().value(for: filter)
        }.count
    }

    func isModified(for filters: [SourceFilter]) -> Bool {
        modifiedCount(for: filters) > 0
    }
}
