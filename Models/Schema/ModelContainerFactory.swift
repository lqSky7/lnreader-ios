// ModelContainerFactory.swift - Opens the v2 store.

import Foundation
import SwiftData

/// Builds the v2 `ModelContainer`.
///
/// v2 lives in its own store file and never opens (or deletes) the v1
/// `default.store`. That separation is what makes the hard break safe: a user
/// who upgrades without a backup still has their old data sitting untouched on
/// disk, and a bridge build can be installed over the app to export it.
enum ModelContainerFactory {

    /// Store file name. Part of the on-disk contract — renaming it looks like a
    /// fresh install to every existing user.
    static let v2StoreName = "LNReader-v2"

    /// Location of the v2 store, for backups and diagnostics.
    static var v2StoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "\(v2StoreName).store")
    }

    /// Build the container for the whole app.
    ///
    /// - Parameter inMemory: use a throwaway store. Previews and tests only.
    @MainActor
    static func makeV2(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            v2StoreName,
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: LNReaderSchemaMigrationPlan.self,
            configurations: configuration
        )
    }
}
