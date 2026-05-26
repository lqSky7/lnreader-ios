// Category.swift - User-defined library categories for organizing novels

import SwiftData
import SwiftUI

/// A user-defined category for grouping novels in the library
@Model
final class Category: Hashable {

    #Unique<Category>([\.name])

    /// Category display name
    var name: String = ""

    /// Sort position for ordering categories
    var sort: Int = 0

    // MARK: - Relationships

    /// Novels assigned to this category
    var novels: [Novel] = []

    // MARK: - Init

    init(name: String, sort: Int = 0) {
        self.name = name
        self.sort = sort
    }

    // MARK: - Defaults

    /// The built-in default category
    static var defaultCategory: Category {
        Category(name: "Default", sort: 0)
    }
}
