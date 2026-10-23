# Paperly document formats v1–v5

Local notebook: `Documents/Paperly/<stable UUID>.paperly/` directory.

```text
manifest.json
strokes/<page UUID>-<write UUID>.drawing
assets/source.pdf                  (optional)
assets/images/<asset UUID>.png      (optional immutable image assets)
```

The manifest stores `formatVersion`, stable notebook `id`, `title`, dates, `generation`, optional `folder`, `cover`, ordered `pages`, and optional `sourcePDF`. Each page stores its stable UUID, template (`blank`, `ruled`, `grid`, `dot`), width/height in points, optional drawing path, zero-based source PDF index, and optional ordered `images`. Dates use Foundation JSONEncoder’s seconds since 2001-01-01. Generation changes with local content/metadata changes.

## Images and version compatibility

New notebooks use format version 2. Readers accept versions 1 through 5; missing `images` decodes as an empty array, so old v1 notebooks need no eager migration. A v1 manifest containing image objects is rejected. Saving image metadata upgrades that notebook to v2. Older Paperly readers that support only v1 cannot open v2 notebooks; this is backward read compatibility, not backward write compatibility.

Each image object stores:

| Field | Meaning |
| --- | --- |
| `id` | Stable object UUID, unique within its page |
| `assetPath` | `assets/images/<UUID>.png`; separate from object identity |
| `x`, `y` | Top-left position in page points before rotation |
| `width`, `height` | Display size in page points |
| `rotation` | Rotation in degrees around the object center |

Array order supplies back-to-front image order. The composition is paper or original PDF, then images, then editable PencilKit ink. Image transforms do not modify PDF or stroke data. Image geometry must be finite; dimensions must be at least 1 and at most 20,000 points. Image paths are restricted to the UUID-named PNG directory and cannot overwrite manifests, PDFs, or strokes. Referenced image bytes are limited to 40 MiB per asset.

Editor import uses ImageIO to validate, apply source orientation, downsample to at most 2048 pixels on the longest side, and encode a single PNG. This stores the normalized image rather than the original source file. Portable archive validation checks manifest references and byte limits; it is not itself a complete image decoder.

## Atomic writes and recovery

Each stroke commit serializes only the affected PKDrawing. It writes a new unique file atomically, atomically replaces the manifest that references it, then updates SQLite. A crash before the manifest commit retains the previous complete state; a crash after it is recovered by reindexing manifests at launch. The predecessor stroke file is removed only after the manifest commit.

Image commits load the latest manifest so image metadata does not overwrite intervening ink changes. New asset bytes are written before their manifest references. Existing image assets are immutable: supplying different bytes under an existing path is rejected. Removing an object changes its page metadata but retains the asset bytes so undo can restore it. Unreferenced image assets are not garbage-collected and remain included in export, increasing retained storage over time. An interrupted insertion may leave an unreferenced asset rather than a manifest pointing to unwritten bytes.

An unexpected termination during a live Pencil gesture may lose that in-progress gesture; completed gestures are queued immediately, with a 350 ms debounce for other drawing changes. Ink and image commits are ordered. Shared undo/redo snapshots cover both kinds of page content, are bounded to 80 history levels, and reset when a page loads; undo history is not part of the document. All persisted generations remain eligible for sync after relaunch because dirty status is derived from manifest generation versus SQLite sync base, not a volatile network queue.

## Portable files and validation

A portable `.paperly` file is a UTF-8 JSON object containing `manifest` and an `assets` map. Asset values are base64 bytes, including exact PKDrawing serialization, the source PDF, image PNGs, and retained optional assets. It is distinct from the local directory. Export assembles the complete container only when sharing or syncing; drawing does not repeatedly serialize the whole notebook. Base64 adds approximately 33% storage overhead. Encoded import is limited to 512 MiB; larger files cannot sync with this version. The container is not streamed or compressed.

Imports reject unsupported versions, duplicate page/image identities, invalid dimensions or transforms, missing referenced assets, oversized referenced images, and absolute/traversal paths. Imported backups receive a new notebook UUID and generation while retaining page/image UUIDs, order, geometry, stroke bytes, PDF bytes, and image assets. A verified remote download keeps notebook identity.

Paperly image clipboard data is a separate format: `app.paperly.image-selection`, version 1, containing one image object plus PNG bytes. Copy also publishes public PNG data; paste validates the payload and creates a new image object/asset. This is Paperly’s own representation, not Goodnotes-compatible serialization. Editable stroke selection copy/cut/paste is delegated to native PencilKit. Clipboard data and undo stacks are not serialized into notebooks.

`metadata.sqlite` is a GRDB-managed derived index and sync journal outside the notebooks. It stores base generation, remote ID/version, and sync state. `Transfers/` contains resumable-upload session records, not tokens. `Thumbnails/` contains disposable reduced-scale image/ink previews; paper templates and PDF remain separate rendering layers. Pen profile, width, and scribble settings are app preferences rather than notebook fields.

## Workspace folders and incoming files

Folders remain the notebook manifest's optional `folder` name. A separate `folders` SQLite table preserves empty workspace folders; creating a folder no longer requires a notebook. Metadata migration seeds this table from existing notebook records, and indexing imported/synced notebook manifests also records their folders. Empty folder entries are not part of an individual `.paperly` archive. Configured Drive clients merge them additively using app-created Drive folders tagged `paperlyWorkspaceFolder=1`. Duplicate concurrent folder creation is coalesced by normalized name in the workspace. Folder deletion uses a separate timestamp/revision tombstone register described below; folder renaming is not exposed. Original iPad builds without this catalog sync discover only folders represented by notebook manifests.

Incoming document copies are staged in the application's `Inbox` directory with a small JSON request before the destination chooser appears. After choosing a location, import commits a notebook and source PDF, removes the staged copy, and opens the returned manifest. A cancelled import removes only its staged request/copy. On relaunch, pending requests resolve their staged filename against the current application container. This uses iPadOS document-type URL delivery for PDF Open In/Copy To; it does not require a shared-container or server-backed share extension.

## Text documents (v3)

Text documents share the notebook UUID, generation, folder, metadata index, portable archive, and Drive history. They use `formatVersion: 3`, an empty `pages` array, no source PDF, and a `textFile` path restricted to `text/<UUID>.json`. Handwritten notebooks still write v2, so adding text support does not needlessly upgrade existing ink files. Old v1/v2 clients reject v3 text documents; update both devices before exchanging text documents.

The content JSON contains `version: 1` and ordered blocks with stable `id`, `kind`, Unicode `text`, and `checked`. Kinds are paragraph, heading1, heading2, bullet, numbered, checklist, quote, and code. Validation requires a nonempty block array, unique block UUIDs, at most 50,000 blocks, at most 2 MiB UTF-8 per block, and at most 32 MiB encoded content. Portable import checks the referenced content, not just its filename.

Text saves write a new content file, commit the manifest and index, then remove the preceding content file. Local text autosave is debounced by 300 ms; background/close/export flush it. One writer drains revisions so an older completion cannot clear newer unsaved changes. Undo/redo is session-only, limited to 100 snapshots. A failed write retains the draft for retry; edits not yet committed when a process is abruptly terminated may be lost. Markdown export preserves block structure and checkbox state but is not an editable `.paperly` backup.


## Supplemental handwriting search terms (v4)

Automatic recognition is a derived local cache in `pageSearch`, keyed by notebook UUID, page UUID (or `text` for text documents), and a source fingerprint. It contains recognized text and a normalized search form, and is not exported. Ink filenames are immutable per save; the fingerprint additionally covers page dimensions and manual search terms. Cache writes and query reads recheck current manifest references. Stale drawing/text revisions cannot appear as valid search hits, and obsolete page rows are pruned. Symbol-containing queries use bound `instr` checks, avoiding FTS punctuation loss and SQL wildcard interpretation.

User-entered page `searchTerms` are authoritative metadata, limited to 64 KiB UTF-8 per page. A notebook with terms writes v4 so older readers reject it rather than silently discarding these terms. Clearing terms does not downgrade the format. Terms travel in the manifest with normal export/import and Drive history, while PKDrawing bytes remain untouched. Untagged ink still writes v2 and text documents v3.

Folder colors live in the workspace `folders` table (`color`, `colorModified`, `colorRevision`) and in app-created Drive-folder properties (`folderColor`, `colorModified`, `colorRevision`). Missing properties default to Blue with a zero revision. Name union preserves empty folders; color merges choose the latest edit time, then revision UUID. Concurrent duplicate Drive folder records coalesce by normalized name. Color metadata does not change notebook generations or overwrite notes; live network sync still needs configured Google OAuth.


## Recoverable deletion (v5)

Moving a document to Trash sets `trashedAt`, creates a new generation, and upgrades the manifest to v5. Optional `trashGroup` identifies documents deleted with a folder. The document directory, source PDF, images, text, and editable strokes remain intact. Restore clears these fields and creates another generation. Sync continues to include trashed documents, so a missing local row cannot accidentally resurrect remote content. A concurrent edit and deletion produces a conflict under the existing generation rules.

Folder metadata stores a deletion flag and optional group under the same timestamp/revision register as its color, including Drive app properties. Restoring a folder restores only documents in that deletion group; restoring one document also reactivates its parent. Folder operations commit per document, so interruption can leave a partial operation, with each committed item recoverable from Trash. Unknown active documents whose folder is tombstoned remain accessible at workspace root. There is no permanent purge or automatic retention expiry. Older clients must be updated before participating in deletion sync.
