# Goodnotes shipped resource findings

Investigation date: 2026-10-22. Scope: only `/Applications/Goodnotes.app`; no account state, user documents, live UI, target execution, or code changes. REA CLI `6.7.0`; no analysis engine installation or configuration changes. These are static declarations, not confirmed runtime behavior. Full REA output envelopes are retained in `static-evidence/`.

## Identity and evidence index

| Label | Operation / resource | Evidence ID |
|---|---|---|
| M | `inspect_macho`, `/Applications/Goodnotes.app/Contents/MacOS/Goodnotes` | `ev_895a29098152643da55e02cde9b5e9feea24bfa1a15c36717b58e00845727dcd` |
| I | `inspect_plist`, `/Applications/Goodnotes.app/Contents/Info.plist` | `ev_75de2698b46d5bcd3806c5faed5c1953df2ed0f7fc11326f0619784ec104de42` |
| T | `inspect_plist`, `/Applications/Goodnotes.app/Contents/Resources/en.lproj/Tools.strings` | `ev_01b5eb430becaa65e783d4f736cd8b0bfea5e11485e92b792ca1f09a194fec1b` |
| L | `inspect_plist`, `/Applications/Goodnotes.app/Contents/Resources/en.lproj/Localizable.strings` | `ev_8ee5ce52976a41f521ec14dea7a8e693c9ee20fbd6275abd8acf483cc8366e7e` |
| C | `inspect_plist`, `/Applications/Goodnotes.app/Contents/Resources/en.lproj/Canvas.strings` | `ev_2e914ff60919f1e17bb9111a0f644eb03475391ad4e25f7f82c957d56264f5a6` |

Observed identity (I): Goodnotes `7.1.30`, build `3962760.264631382`, bundle ID `com.goodnotesapp.x`. Native binary SHA-256 (M): `d3ab130294dd36106d8a01e08cad1d6d50010af6171a934af4404ccb08dc01a6`. Universal x86_64 and arm64, selected arm64, MACCATALYST build metadata. M lists no `LC_ENCRYPTION_INFO*` command for the selected slice; this does not establish lack of every protection mechanism. No decryption attempted.

Resource entries are under `data.normalized_result.value` in each JSON. M has import/export coverage limitations for stripped/toolchain-hidden symbols and normalizes build metadata from otool, retaining vtool provenance. No native functions were decompiled, traced or executed. T/L report no parser limitations. C had no matches for the focused feature terms and adds no behavior evidence.

## Feature ledger

### Pens — partially answered

Observed (T): `pen_style_option_fountain_pen`, `pen_style_option_ball_pen`, and `pen_style_option_brush_pen` label Fountain Pen, Ball Pen, and Brush Pen. Relevant setting identifiers are:

- `pressure_sensitivity_option_title` with `pressure_sensitivity_option_min/max`.
- `tip_sharpness_option_title` with `tip_sharpness_option_sharp/round/blunt`.
- `tip_roundness_option_title` labels Tip Flatness; `tip_flatness_option_flat` supplies the flat endpoint.
- `pen_stabilization_option_title` labels stroke stabilization.
- `pen_settings_react_to_writing_speed` labels speed based thickness adjustment.
- `pen_settings_barrel_roll` labels reaction to pen rotation.
- `pen_settings_action_save_pen_style`, `saved_styles_success_toast` declare saving the current style.
- `pen_stroke_style_option_solid/dotted/dashed/none` and `pen_stroke_style_type_button` declare stroke type options; `pen_option_thickness` declares thickness.
- Color picker sections declare presets, custom colors and history; add/remove/restore preset actions also exist.

Inference: style selection and adjustable rendering parameters are explicit product concepts. Resource strings alone do not prove which controls each style exposes, exact slider ranges/defaults, stroke equations, or the hardware requirements. The `none` stroke type might be relevant only to shapes and must not be assumed to mean an invisible pen.

Paperly implication (design choice): expose the three named pen styles and common thickness/color control. Different pressure/speed/shape behavior requires an independently designed renderer; no Goodnotes algorithm was recovered. Root UI evidence should decide style-specific control placement.

### Scribble to Erase — partially answered

Observed (T): `pen_gestures_options_title`, `pen_gestures_options_scribble_to_erase_title`, and its footer declare a pen gesture which removes handwriting and drawings when scribbled over. `pen_gestures_options_scribble_to_erase_shapes_title` declares a separate Shapes and Highlighter inclusion option. `pen_gestures_options_circle_to_lasso_title/footer` declares a separate circling selection gesture.

Observed eraser context (T): object/entire-stroke, pixel, precision, and standard eraser labels coexist; object description says touching a stroke removes it, pixel description specifies fine local erasure. There are highlighter-only/tape-only filters and an auto-deselect option. Their coexistence does not establish visibility in one menu.

Unknown: gesture classifier thresholds, crossing/coverage criteria, duration, movement tolerance, pressure dependence, default toggles, deletion timing, minimum target count, handling of locked images or selection, and how the gesture coexists with ordinary zigzag writing.

Paperly implication (design choice): implement scribble recognition separately from drawing with undo as one operation, only remove eligible intersected strokes, and provide a setting. Conservative thresholds must be tuned using independent examples; resource copy cannot supply them.

### Image insertion — partially answered

Observed (L): `photo_library_picker_title`, `photo_library_picker_insert_from_files`, `photo_library_picker_insert_from_photos`, `action_image`, `menu_action_import_image`, and `toolbar_overflow_menu_images` declare Images with Files/Photos sources. Camera and Image Playground resources also exist; their availability on this Mac is unknown. Invalid-image and unavailable-source errors are declared.

Observed (T): `image_action_crop`, `menu_item_title_image_crop`, `lock_image`, `unlock_image`, and `image_option_add_page_previous/next/last` declare crop, lock/unlock, and image-as-page actions. Observed (I): image document support declares TIFF, JPEG, GIF, PNG, BMP, ICO and X bitmap UTIs. This declaration is not a runtime image-decoder compatibility test.

Paperly implication (design choice): a file picker, image insertion into the note, select/move/resize/crop affordances, and image persistence are a reasonable feature path. Exact insertion coordinates, default dimensions, crop shape, drag/drop behavior, constraints and undo semantics remain unknown from static evidence.

### Clipboard and selection — partially answered

Observed (I): exported composite-content pasteboard types:

| Declared type | Description |
|---|---|
| `com.goodnotesapp.goodnotes5.notes` | GoodNotes Lasso Pasteboard |
| `com.goodnotesapp.goodnotes5.text` | GoodNotes Text Pasteboard |
| `com.goodnotesapp.goodnotes6.textBox` | GoodNotes Text Pasteboard |
| `com.goodnotes.image` | GoodNotes Image |

Observed (L): `action_copy`, `action_cut`, `action_paste`, `copy_text`, `notes_organisation_edit_hw_copy_as_text`; lasso inclusion toggles for handwriting, images, text boxes, shapes and other element categories. Freehand and rectangular lasso labels exist. Observed (T): `text_selection_menu_paste_and_match_style`. These strings do not prove any keyboard bindings or serialization payloads.

Inference: Goodnotes declares richer internal object exchange than plain image-only clipboard data. Unknown: binary/JSON serialization, external-app fallback formats, PNG/TIFF representations, text/ink conversion behavior, selection offset and repeated paste positioning, clipboard permission handling and keyboard shortcuts.

Paperly implication (design choice): use a Paperly-owned clipboard payload with plain text/image interoperability, support stroke and image objects, and use one undo item for a paste/cut. Do not adopt Goodnotes' private UTIs or imply payload compatibility.

## Search boundary and independent shell observations

`rg --files` inventoried only shipped app resource paths. Focused format-aware `plutil -convert json` reads examined English Tools, Localizable, Canvas, GN6ToolbarUI and Settings string tables for pen/erase/image/paste/lasso terms. `source-hashes.json` contains independent Python SHA-256 checks of the two useful string tables. Those shell reads are auxiliary observations, not REA Evidence records. Findings above use the retained REA parses as their primary source. Other localizations, frameworks, hidden feature flags, and native algorithm implementations were not investigated.
