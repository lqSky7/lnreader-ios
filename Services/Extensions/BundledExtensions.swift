// BundledExtensions.swift - Extensions shipped inside the app.
//
// Repositories are how extensions arrive in the long run (ExtensionRepoService),
// but a first-party port ships with the binary so it works on a fresh install
// with no repository configured.

import Foundation

enum BundledExtensions {

    /// Extensions compiled into the app bundle, installed on launch.
    ///
    /// `Resources/mangafire.js` is a copy of
    /// `lnreader-extensions/extensions/mangafire/mangafire.js`; that repository
    /// is the source of truth.
    static let all: [InstalledExtension] = [
        InstalledExtension(
            pkg: "all.mangafire",
            name: "MangaFire",
            lang: "en",
            versionId: 1,
            iconURL: nil,
            kind: .manga,
            repoBaseURL: nil,
            installedAt: .distantPast
        ),
    ]

    /// Resource name for a bundled extension, or `nil` when it has none.
    private static func resourceName(for pkg: String) -> String? {
        pkg == "all.mangafire" ? "mangafire" : nil
    }

    /// Copy any bundled extension that is not installed yet into the store.
    ///
    /// Installed copies are left alone: a user who updates an extension from a
    /// repository must not be rolled back by the version in the binary.
    static func installMissing() {
        for info in all where !ExtensionStore.isInstalled(info.pkg) {
            guard let name = resourceName(for: info.pkg),
                  let url = Bundle.main.url(forResource: name, withExtension: "js"),
                  let bundle = try? String(contentsOf: url, encoding: .utf8)
            else { continue }

            try? ExtensionStore.install(info, bundle: bundle)
        }
    }
}
