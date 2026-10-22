# Migrating to LNReader v2

> ⚠️ **Breaking change.** LNReader v2 does **not** read data from v1. Your library, reading progress, categories, history and settings must be exported from v1 and imported into v2. There is no automatic upgrade.

## What changed and why

v2 adds manga support: Mihon/Yokai-compatible extensions, a manga reader, downloads, AniList tracking and encrypted backups. To support this, the database was rebuilt from scratch. Carrying the old format forward would have meant keeping legacy code in the app forever, so v2 starts clean and imports a backup instead.

**Cloud sync also changed.** v1 uploaded your library to the server as readable JSON. v2 uploads only an **end-to-end encrypted** backup that the server cannot read. The old sync endpoint is turned off. Your account still works, but the data stored by v1 sync does not appear in v2 by itself.

## Recommended path: export from v1 before upgrading

1. Install the **v1-final** build. It's the last v1 release and adds one feature.
2. Open **More → Export for v2**, then save the `.tachibk` file to Files or AirDrop it somewhere safe.
3. Install v2.
4. On first launch, tap **Import backup** and pick the file.
5. Once everything looks right, tap **Delete old data** to free up space.

## Already upgraded without exporting?

v2 never deletes your v1 data unless you tell it to. To recover:

1. Install the **v1-final** build over v2. Your old data is still on the device.
2. Export as in step 2 above.
3. Reinstall v2 and import the file.

## Only have cloud data? (v1 sync, no device data)

Convert the old sync data on a computer:

```sh
# Signs in with your LNReader account (asks for your password), downloads your v1 sync data and converts it
swift run --package-path Packages/LegacyBackupConverter lnr-convert --email you@example.com -o backup.tachibk

# Or convert a sync JSON file you already saved
swift run --package-path Packages/LegacyBackupConverter lnr-convert sync.json -o backup.tachibk
```

Then import `backup.tachibk` in v2.

This path only includes what v1 synced: your library, chapters with their read, bookmark and progress state, and installed sources. **Categories, history and settings are not included.** The old cloud data will be deleted after a migration window, so convert it before then.

## What carries over

| Data | v1-final export | Cloud conversion |
|---|---|---|
| Library novels and metadata | ✅ | ✅ |
| Chapters: read, bookmark, progress, paragraph position | ✅ | ✅ |
| Installed sources (reinstalled on import) | ✅ | ✅ |
| Categories and library order | ✅ | ❌ |
| Reading history | ✅ | ❌ |
| General, reader and TTS settings | ✅ | ❌ |

## What does not carry over

- Downloaded TTS audio. Download it again in v2.
- Imported local EPUB/PDF files. Re-import them.
- Profile avatar.
- NovelFire login and comments. Sign in again.
- Downloaded-chapter flags.

## Interoperability bonus

v2 backups are `.tachibk` files compatible with Mihon and Yokai. You can import a Mihon or Yokai backup into v2 to bring your manga library, progress and trackers across. A v2 backup imported into Mihon or Yokai restores its manga portion; Mihon and Yokai ignore the novel data.
