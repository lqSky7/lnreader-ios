// SchemaMigrationPlan.swift - Keeps future schema changes migrating properly.

import Foundation
import SwiftData

/// Migration plan for the app store.
///
/// There is one version today. Every future change to `SchemaV1` must instead
/// add a `SchemaV2` plus a `MigrationStage`, so shipped builds never have to
/// guess what the on-disk shape used to be.
enum LNReaderSchemaMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
