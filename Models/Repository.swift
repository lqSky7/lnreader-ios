// Repository.swift - Plugin repository URLs for source discovery

import SwiftData
import SwiftUI

/// A plugin repository that provides novel source plugins
@Model
final class Repository: Hashable {

    #Unique<Repository>([\.url])

    /// The repository's JSON endpoint URL
    var url: String = ""

    // MARK: - Init

    init(url: String) {
        self.url = url
    }

    // MARK: - Defaults

    /// Default plugin repository URL
    static let defaultURL =
        "https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json"
}
