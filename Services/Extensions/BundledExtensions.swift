// BundledExtensions.swift - Extensions shipped inside the app.
//
// Repositories are how extensions arrive in the long run (ExtensionRepoService),
// but a first-party port ships with the binary so it works on a fresh install
// with no repository configured.

import Foundation

enum BundledExtensions {

    /// Extensions compiled into the app bundle, installed on launch.
    ///
    /// Each `Resources/<id>.js` is a copy of
    /// `lnreader-extensions/extensions/<id>/<id>.js`; that repository is the
    /// source of truth. Raise `versionId` when the copy changes: an installed
    /// bundle that came from the binary is replaced when the binary's is newer.
    ///
    /// `mihonID` is the Mihon/Yokai source id the upstream extension has, so a
    /// `.tachibk` backup can be matched to the bundle that replaces it.
    static let all: [InstalledExtension] = [
        InstalledExtension(
            pkg: "all.mangafire",
            name: "MangaFire",
            lang: "en",
            versionId: 2,
            iconURL: nil,
            iconAsset: "MangaFireIcon",
            kind: .manga,
            repoBaseURL: nil,
            installedAt: .distantPast
        ),
        InstalledExtension(
            pkg: "all.allmanga",
            name: "AllManga",
            lang: "en",
            versionId: 3,
            iconURL: nil,
            kind: .manga,
            repoBaseURL: nil,
            installedAt: .distantPast
        ),
    ]

    /// Mihon source ids (`Backup.sources`, `BackupManga.source`) handled by a
    /// bundled extension, mapped to its package id.
    static let mihonSourceIDs: [Int64: String] = [
        6_084_907_896_154_116_083: "all.mangafire",
        4_709_139_914_729_853_090: "all.allmanga",
    ]

    /// Resource name for a bundled extension, or `nil` when it has none.
    private static func resourceName(for pkg: String) -> String? {
        switch pkg {
        case "all.mangafire": "mangafire"
        case "all.allmanga": "allmanga"
        default: nil
        }
    }

    /// Copy any bundled extension that is not installed yet into the store, and
    /// backfill metadata that older builds did not write.
    ///
    /// Installed *bundles* are left alone: a user who updated an extension from
    /// a repository must not be rolled back by the version in the binary.
    static func installMissing() {
        for info in all {
            guard let name = resourceName(for: info.pkg),
                  let url = Bundle.main.url(forResource: name, withExtension: "js"),
                  let bundled = try? String(contentsOf: url, encoding: .utf8)
            else { continue }

            if !ExtensionStore.isInstalled(info.pkg) {
                try? ExtensionStore.install(info, bundle: bundled)
                continue
            }

            // A newer bundled version replaces an older bundled one. Anything
            // installed from a repository is the user's choice and stays.
            if let stored = ExtensionStore.installed().first(where: { $0.pkg == info.pkg }),
               stored.repoBaseURL == nil, stored.versionId < info.versionId {
                var upgraded = info
                upgraded.iconAsset = info.iconAsset ?? stored.iconAsset
                try? ExtensionStore.install(upgraded, bundle: bundled)
                continue
            }

            // Already installed: only repair missing metadata (e.g. an icon
            // added in a later build), keeping the installed bundle bytes.
            guard let stored = ExtensionStore.installed().first(where: { $0.pkg == info.pkg }),
                  stored.iconAsset == nil, info.iconAsset != nil,
                  let installedBundle = ExtensionStore.bundle(for: info.pkg)
            else { continue }

            var repaired = stored
            repaired.iconAsset = info.iconAsset
            try? ExtensionStore.install(repaired, bundle: installedBundle)
        }
    }
}
