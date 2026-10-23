# Validation

Development host: Xcode 26.4.1, Swift 6 language mode. Target: iPadOS 17+. Simulator runtime: iPad Pro 13-inch (M5), iPadOS 26.4.

- Initial complete simulator build passed for arm64 and x86_64.
- Initial Foundation-only test run: 5 tests passed, zero failures (serialization, validation and conflict matrix).
- Independent code review identified and verified fixes for preserving unsaved ink after a write failure, blocking edits after failed page loading, consistent PDF media-box geometry, and stopping export after failed autosave.
- Additional failure recovery, repository import and deduplicated/merged remote-head tests are included.

This file is updated with the final run outcomes before handoff. OAuth and real cross-device Drive transfers need a configured developer-owned client. Hardware Pencil performance/palm rejection are not established by simulator tests.

## Previous baseline results

- `swift test --jobs 1`: **6 tests passed**, zero failures.
- Xcode iPad simulator test action: **5 tests passed**, zero failures. This includes a real editable PencilKit stroke round-trip, import/replacement with optional assets, preservation of live ink after a forced storage failure, and noneditable behavior after corrupt stroke decoding.
- Final iPad-only simulator build: **BUILD SUCCEEDED**. Built Info.plist declares `UIDeviceFamily = [2]`. The final build also adds PDF-view page caching and cold-launch document import handling.
- App installed and launched on the iPad Pro 13-inch simulator. Visual inspection is limited to the tested simulator; hardware and live Google account validations remain outstanding.
- An earlier rerun hit host disk exhaustion; a clean retry after removing project-generated caches passed. No user documents were removed.

Visual review returned a scoped **ship** verdict for the five simulator captures: light library/editor/settings and dark accessibility-large library/settings. The account panel was adjusted and recaptured to avoid clipped words. This covers iPad Pro 13-inch portrait only; other sizes/orientations, editor dark/large-text presentation and cropped/rotated PDF alignment were not visually validated. Review images are local ignored artifacts under `.impeccable/review/`.


## Editor feature pass — final results

The feature pass adds three native PencilKit pen profiles, a Paperly-owned geometric Scribble to Erase recognizer, editable image objects, image/ink clipboard handling, and shared page-local undo/redo.

- Final Foundation run: **18 tests passed**, zero failures. Run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path /tmp/paperly-core-xcode-final --jobs 2`. A fresh scratch path avoids mixing host Command Line Tools and Xcode Swift module caches.
- Final iPad simulator test action: **23 tests passed**, zero failures. This includes immediate undo before a pending lasso commit, selected-image clipboard routing, image-only transparent thumbnail pixels, and image export over a source PDF whose original text remains extractable.
- The Photos presentation fix: **BUILD SUCCEEDED**, installed and checked interactively. The final full Xcode test rerun after explicit image-mode PNG routing also passed all **23 tests**. Its menu button now presents a PhotosPicker attached to the persistent editor view.
- Save serialization and thumbnail composition run off the drawing thread; thumbnail writes share the serialized save chain and reject stale revision tickets.

Current test sources cover:

- v1 decoding without image fields; v2 ordered image geometry/asset round-trip; invalid image paths, sizes, identities, transforms, references, and byte limits.
- Synthetic scribble classification under rotation/translation, sampling/jitter, and rejection of ordinary lines, circles, smooth waves, slow or oversized gestures, and invalid input.
- PencilKit scribble integration: transformed hit testing, eligible overlapping pen strokes, optional highlighter inclusion, unrelated ink preservation, and retaining a scribble with no eligible target.
- Image insertion, move, delete, undo, repository relaunch, and interleaved ink/image saves; versioned image clipboard payloads, PNG normalization, alpha, orientation, and invalid/oversized inputs.
- Immediate undo of a debounced lasso change, image-plus-original-PDF export, image-only transparent thumbnail composition, and selected-image clipboard command routing and public PNG paste in image mode. Native ink clipboard behavior was checked interactively, not through a synthetic canvas selection API.

Live simulator checks used a separate `Editor feature check` notebook and the project-owned Paperly logo. Verified pen panel/width preview and gesture controls; PhotosPicker selection and insertion; image accessibility move, 90° rotation, copy/paste as two editable objects, Undo/Redo, and a populated page thumbnail. Native PencilKit Select All followed by Paperly toolbar Copy/Paste produced a second ink stroke in the accessibility tree; toolbar Undo removed that stroke and enabled Redo. No Goodnotes private clipboard encoding was used. The initial attempted unit test called unsupported `selectAll` directly on PKCanvasView and was replaced with public routing checks; it is not counted as a passing native lasso test.

New local captures are `.impeccable/review/pen-settings.png`, `image-paste.png`, and `native-ink-paste-undo.png` (ignored generated artifacts). The prior five-capture visual verdict covers the earlier UI. The new pen-settings and image-paste captures received a separate scoped **ship** verdict with no material visual issue; that review covers these light-mode portrait states only. Physical-iPad checks remain outstanding: false-positive/missed scribble tuning, Pencil pressure/latency/palm rejection, full drag/resize behavior, Files provider variations, and cross-app PNG clipboard behavior. Automated clipboard tests do not establish interoperability with every external app. Cropped/rotated PDF alignment, live OAuth, and cross-device Drive transfers remain outside the recorded validation.

The [interaction study](GoodnotesResearch/INTERACTION_FINDINGS.md) records observed Goodnotes affordances and its evidence limits; [static findings](GoodnotesResearch/STATIC_FINDINGS.md) record shipped resource declarations. Neither establishes recovered native rendering or gesture algorithms. Paperly uses PencilKit profiles and its independently designed geometric recognizer, not copied proprietary implementations.

## Physical iPad installation — 2026-10-22

Signed arm64 device build succeeded with the selected Personal Team. Installed `app.paperly.ipad` on the connected iPad (9th generation), iPadOS 18.7.7. Developer Mode was enabled and the user trusted their development profile; CoreDevice then confirmed successful launch. The embedded profile includes this device and expires 2026-10-29. This establishes build/install/launch only; the user is performing handwriting and hardware interaction testing.

## Page zoom and pull-to-add — 2026-10-22

- Native UIScrollView wraps the complete SwiftUI page; pinch scales paper, ink, images and PDF together from fit through 6×. Page-space coordinates remain unscaled for storage. Zoom survives normal editor updates; a page turn resets to fit. One-finger/Pencil ink remains available; panning uses two fingers except in Pencil-only mode. Image editing always reserves one-finger dragging for objects.
- Explicit edge overscroll of 72 viewport points arms a page turn, or append at the last page. A release label and haptic feedback mark the threshold. Returning below the threshold cancels. Only drag release triggers navigation; pinch bounce and deceleration do not. Vertical is the default; horizontal is configurable. Navigation flushes ink first and rejects duplicate requests while loading.
- **20 core tests and 25 iPad tests passed**, zero failures. New tests exercise edge/interior/diagonal/invalid pull geometry, zoom coordinate round-trip, retaining zoom during updates, page reset, touch-count policy, save-before-append, template inheritance and duplicate/stale page requests.
- Simulator and signed physical-device builds succeeded. Updated app installed and CoreDevice confirmed launch on the connected iPad. Native portrait viewport and image placement inspected in Simulator; capture: `.impeccable/review/page-viewport.png`. Live two-finger pinch/pull feel and zoomed handwriting require the user's physical-iPad check; programmatic UIKit zoom tests are not a claim of multitouch hardware validation.

## Workspace, continuous pages, PDF import, and black ink — iPad update

Changes were initially tested in Simulator while the user held the device update. On October 22, 2026, the user authorized deployment: the signed physical-device build succeeded, CoreDevice installed it over the existing app on the connected iPad, and launch succeeded. The running Paperly process was confirmed afterward. Build log: `/tmp/paperly-workspace-device-build.log`.

- Final simulator test run: **32 tests passed**, zero failures (`/tmp/paperly-batch-confirmed-tests.log`). The unchanged Foundation core previously passed 20 tests. New cases cover empty-folder persistence/root filtering, staged PDF restoration/destination assignment, continuous document size and lazy page caching, shared tools with independent per-page ink/undo, image recovery after cache eviction, and black ink rendering in a dark parent appearance without changing serialized strokes.
- White paper canvases and pen previews explicitly use light appearance. Rasterized ink resolves under light traits for thumbnails and PDF output. Black-pixel and trait inheritance checks pass. This addresses PencilKit's automatic dark-appearance ink conversion over permanently white paper.
- The active UI now uses a continuous scroll document with nearby editable page hosts. Layout/toolbar updates preserve the last edited page for Undo; scroll-driven focus cannot interrupt an in-progress stroke. Offscreen models are flushed before their model/hosting view are discarded together. Pinch zoom remains; persistent gesture instructions and the zoom percentage were removed.
- Native UI check used a project-owned two-page PDF staged through the same inbox restoration path: destination picker appeared, a new Course notes folder was created/selected, Import & Open opened the PDF, and Workspace → folder showed only that folder's notebook. PDF page text remained present. Document-type registration includes `com.adobe.pdf` and the existing file-URL handler stages copies before destination selection. Actual PDF handoff from third-party iPad apps remains to be checked on the updated device; no separate share extension was introduced.
- First-pass capture: `.impeccable/review/import-destination.png`. Folder and editor states were inspected through native accessibility/screenshots. Live continuous-scroll/pinch feel on physical hardware remains unvalidated for this installed build.


## Universal iPhone/iPad client, text documents, shared workspace, and page navigation

The target now supports device families 1 and 2 with the existing bundle ID. iPhone/iPad use one shared workspace screen (folder-first, matching folder cards, text/ink covers, grid/list, filters, sorting, creation/import actions); compact width changes only navigation and available column count. Mac remains a planned client, not a built target.

- 43 tests passed on iPhone 17 Pro Simulator (`/tmp/paperly-final-universal-tests.log`) and iPad Pro 13-inch Simulator (`/tmp/paperly-final-ipad-tests.log`). The portable Foundation suite passed 22 tests (`/tmp/paperly-final-core-tests.log`). The keyboard-focus correction passed all 43 tests (`/tmp/paperly-confirmed-universal-tests.log`). The final navbar/accessibility pass also passed all 43 (`/tmp/paperly-navbar-accessibility-tests.log`). The logo-only addition built successfully (`/tmp/paperly-phone-brand-build.log`).
- Text coverage includes archive import/export and malformed content rejection; v2 compatibility; mixed workspace type filters; latest-revision autosave and reopen; Unicode block splitting and checklist continuation; move/delete/undo/redo; failed-write draft retention/retry; and Markdown fences/checks/numbering.
- Empty workspace folders merge additively, with whole-operation validation before writes. Local persistence and merge tests pass. The Drive adapter creates app-tagged folders and coalesces concurrent duplicate names in the app. OAuth remains unconfigured, so live cross-device folder/document sync is not claimed.
- Paged view fits a full page in each viewport slot, snaps swipes to an adjacent page at fit zoom, and permits free panning while zoomed. Adding a page activates it and requests a fresh fit. Tests verify viewport geometry, snapping targets, active-page identity, and fit reset. Continuous mode remains available.
- Motion uses native navigation, short workspace transitions and selected-tool feedback, and UIKit programmatic page scrolling. Reduce Motion removes spatial animations. Hardware animation smoothness, Pencil latency, and physical swipe feel require device testing.
- An initial cold iPad Simulator launch failed before the test runner obtained a process. Warming the Simulator and rerunning succeeded with all 43 tests. No physical device was updated during this universal-client pass.

- Native iPhone Workspace / Recents / Settings bottom tabs were inspected in Simulator. The supplied transparent mark and Paperly wordmark appear only at the phone Workspace root, preserving folder Back navigation and iPad layout.
- Separate text/ink fixtures were inspected in both Simulators without editing existing user documents. Text layout/selection was checked. Accessibility `setValue` changes the native view without a typing callback, so it is not counted as an autosave runtime test; persistence is covered by repository/view-model tests. Live keyboard composition remains a manual check.
- Dark Mode with accessibility-large text exposed cramped phone grid cards. The final pass uses wider columns and wrapping titles at accessibility sizes. Simulator text was then restored to normal (`large`) and appearance to Light at the user's request. Hardware smoothness and live Google sync remain unvalidated.

- Final phone-only logo placement confirmed in the native iPhone Workspace navigation bar at normal text size. Capture: `.impeccable/review/universal-iphone-workspace.png`. The iPad mark is unchanged.

- Phone logo alignment correction: removed the compressed wordmark beside the image and centered the 28 pt mark in an explicit 44 pt frame. Simulator build succeeded (`/tmp/paperly-centered-logo-build.log`); native iPhone screenshot confirmed alignment. No storage or editor behavior changed.


## Folder colors, local search, and Trash (2026-10-22)

- Universal Simulator build passed (`/tmp/paperly-trash-build.log`); final UI copy/count adjustment build passed (`/tmp/paperly-trash-final-build.log`).
- All 53 iOS tests passed on iPhone 17 Pro (`/tmp/paperly-trash-tests.log`), plus 26 Foundation tests on macOS (`/tmp/paperly-trash-core-tests.log`). The Foundation command requires `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; the initial command without it could not locate XCTest.
- Coverage includes folder color persistence, timestamp/revision merges, source-fingerprint search invalidation, symbol aliases, text-body search, portable supplemental search terms, stale recognition rejection, and a printed Vision OCR control. That control does not establish accuracy on cursive handwriting or equations.
- Trash tests cover durable manifest deletion, editable bytes preserved through export/reopen/restore, deletion-versus-edit sync decisions, grouped folder recovery excluding earlier deletions, empty folder restore, old folder catalog merges, and workspace/Recents/Trash filtering including concurrent orphan documents. Live Google Drive transfers were not tested because OAuth is unconfigured.
- Native iPhone checks: folder palette in Dark appearance; text-body search; folder deletion confirmation; disappearance from Workspace; deleted folder contents; grouped restore; restored color and both document types.
- Native iPad checks: Trash sidebar visible; document menu and confirmation; deleted text document disappears. Simulator coordinate automation failed to select the sidebar, so iPad Restore UI was not manually verified. The preview fixture was restored directly during cleanup, and the shared repository restore behavior is covered by tests.
- No physical iPad installation was performed in this pass. No permanent-delete function or retention expiry is provided. All clients must be updated for v5 deletion manifests.


## Physical iPhone deployment (2026-10-22)

Built the current universal app for the connected iPhone 17 using the existing development team and bundle identifier. Device build passed (`/tmp/paperly-iphone-device-build.log`); CoreDevice confirmed installation over the existing app and successful launch. This updates the phone without uninstalling its data container. Hardware handwriting/gesture quality and live Drive sync still require user testing.


## Physical iPad update (2026-10-22)

The latest universal app built successfully for the connected iPad (9th generation), using the existing development team and bundle identifier (`/tmp/paperly-ipad-latest-device-build.log`). CoreDevice confirmed installation over the existing app and successful launch. The app was not uninstalled, preserving its data container. Both the physical iPhone and iPad now have this feature build.


## Google OAuth configuration deployment (2026-10-22)

Configured the supplied public iOS OAuth client ID and derived reversed URL scheme in Config.xcconfig. Device build passed (`/tmp/paperly-google-oauth-device-build.log`); checked the built Info.plist for exact client ID, callback scheme, and unchanged bundle identifier. CoreDevice confirmed installation on iPad and paired iPhone; the first iPhone connection failed and one retry succeeded. iPad launch succeeded. Google consent/sign-in and live Drive transfers remain unverified until the user signs in.


## Device archive path fix (2026-10-22)

A sync error reported a missing stroke file. Read-only copies of both physical devices' Documents/Paperly folders showed all current manifest assets present, including the reported phone stroke file. Foundation enumeration resolves symlink aliases (`/var` to `/private/var`), while export stripped the unresolved base path length; this produced incorrect archive keys. `exportData` now resolves the base before enumeration and verifies that each enumerated path stays below it. No notebook content was rewritten or discarded.

A new symlink-root test failed before the patch and passed afterward, checking ink asset keys, portable import, and text-document export. All 54 iOS tests passed (`/tmp/paperly-sync-path-fixed-tests.log`); the device build passed (`/tmp/paperly-sync-path-device-build.log`). CoreDevice confirmed installation on both physical devices. Diagnostic copies remain local under `/tmp/paperly-sync-diagnosis-{iphone,ipad}-20261022`.


## Relative enumeration and physical export verification (2026-10-22)

The initial canonical-prefix patch passed Simulator tests but the phone still reported unsafePath. Export now uses FileManager's relative-name enumerator directly and validates each relative name; no absolute prefix comparison or length stripping remains. Four repository tests passed on Simulator (`/tmp/paperly-relative-export-tests.log`). A fifth test creates an isolated repository beneath URL.documentsDirectory, matching PaperlyApp's physical sandbox path source. All five repository tests then passed on the physical iPhone 17 (`/tmp/paperly-physical-iphone-export-tests.log`), after the user unlocked it. These cover Documents-root ink/text exports, symlink-root exports/import, original portable ink round-trip, imported assets, and conflict decisions. The test probe uses its own UUID folder outside Documents/Paperly and cleans up only that probe.

The normal device build passed (`/tmp/paperly-relative-export-final-device-build.log`) and CoreDevice confirmed replacement installation on iPhone and iPad. Google Drive cloud transfer remains a separate verification step pending user retry.


The user retried syncing in the updated build and confirmed **Synced with Google Drive**. This confirms the reported missing-asset/unsafe-path blocker is resolved in the live flow. A byte-for-byte cross-device round-trip was not independently audited in this pass.


## Silent editor autosave (2026-10-22)

Removed the notebook header's changing save-status subtitle and the text editor's principal save-status toolbar item. Text error recovery now has an inline Retry beside its existing error message. Autosave, debounce, close/background flush, and Drive sync code were unchanged. Device build passed (`/tmp/paperly-quiet-autosave-device-build.log`), and CoreDevice confirmed installation on both physical devices. No additional tests were added for this presentation-only removal.
