// SchemaMigrationPlan.swift - Keeps future schema changes migrating properly.

import Foundation
import SwiftData

/// Migration plan for the app store.
///
/// V1 → V2 adds `Chapter.hidden` (default false) and an index, which is a
/// lightweight change. Every future change to `SchemaV2` must add a `SchemaV3`
/// plus a `MigrationStage`, so shipped builds never have to guess what the
/// on-disk shape used to be. Rows migrated from V1 start unhidden;
/// `LibraryMaintenance.reconcileVisibility` fills the column in once.
enum LNReaderSchemaMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}
