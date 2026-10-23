---
name: Paperly iPad
description: Quiet native notebooks with tactile pastel covers and white writing paper.
colors:
  paper: "#ffffff"
  cover-blue: "rgb(57%, 71%, 89%)"
  cover-sand: "rgb(88%, 83%, 72%)"
  cover-sage: "rgb(64%, 76%, 65%)"
  cover-lavender: "rgb(72%, 68%, 84%)"
  paper-guides: "rgb(78%, 83%, 90%)"
typography:
  display:
    fontFamily: "-apple-system"
  title:
    fontFamily: "-apple-system"
  body:
    fontFamily: "-apple-system"
  label:
    fontFamily: "-apple-system"
rounded:
  card: "16pt"
  cover: "10pt"
  page: "8pt"
  selected-tool: "12pt"
spacing:
  content: "28pt"
  grid: "20pt"
  paper: "32pt"
components:
  notebook-cover:
    rounded: "{rounded.cover}"
    width: "168pt"
    height: "218pt"
  writing-control:
    size: "44pt"
---

# Design System: Paperly iPad

## Overview

The user-supplied Goodnotes-inspired reference screens govern this world: a quiet pale sidebar, blue selection, tactile pastel covers, white paper, and floating writing controls. Writing and finding notebooks take priority over decoration. Preserve this established direction when adding screens.

This is a native iPadOS interface built with SwiftUI, UIKit, PencilKit, and PDFKit. Use native navigation, forms, sheets, menus, importers, sharing, and SF Symbols. Reference images are design evidence; their notebook and account contents are not application data.

## Colors

Blue is the primary action tint. SwiftUI `.blue` and `.accentColor` supply actions and selected states; selected sidebar rows use accent opacity (0.13), and selected writing tools use accent opacity (0.12).

Use UIKit `systemBackground` for the library and editor shell, `secondarySystemBackground` for the sidebar and writing surround, and SwiftUI `primary` and `secondary` for text. These native semantic colors follow the appearance preference; do not freeze them to sampled hex values. Notebook cards use a semantic separator stroke at opacity (0.35).

Pastel blue, sand, sage, and lavender covers use the frontmatter palette with native gradients. Writing paper remains white in every appearance. Paper guides use the fixed guide color; line guides reduce it to opacity (0.65). Ink is independent of interface appearance, with black, blue, red, green, purple, and a custom color picker.

## Typography

Use the system family and semantic SwiftUI text styles with Dynamic Type. Library and sidebar headings use `largeTitle.bold`; notebook card and editor titles use `title3.bold`; list titles use `headline`. Actions and navigation use body styles, with semibold selection. Supporting information uses `subheadline`, page metadata uses `caption`, and sync metadata uses `caption2`. Page numbering uses monospaced digits. Avoid converting semantic styles into fixed point sizes. At accessibility Dynamic Type sizes, the sidebar Google Drive account panel becomes a full-width, vertically expanding text stack so account status can wrap without clipped words; the regular-size icon and chevron arrangement is reserved for smaller type.

## Layout

`NavigationSplitView` owns sidebar/detail adaptation. The sidebar spans a minimum (240 pt), ideal (280 pt), and maximum (320 pt) width. Native compact presentation remains under system control; do not introduce web breakpoints.

The library uses the content inset and grid gap from frontmatter. Adaptive grid columns span (235–360 pt). Grid covers use the notebook-cover dimensions; the list uses smaller covers (54 × 70 pt). The heading offers grid/list presentation, while search and sort use native controls. The sidebar contains Library, Recents, populated Folders, Settings, and Google Drive connection status.

Opening a notebook presents the editor full screen. Its page retains document dimensions and scales to fit the available area. The floating toolbar uses `ViewThatFits` to change from one row into two rows when needed, with safe areas preserved. Drawing controls have the frontmatter touch size; the page selector has a minimum height (44 pt).

## Elevation & Depth

Tonal surfaces establish the shell. Covers use a native gradient, a slim spine detail, and a black shadow at opacity (0.14), radius (10 pt), offset (0, 9 pt). The page has a lighter shadow at opacity (0.07), radius (15 pt), vertical offset (5 pt). The writing toolbar uses native `regularMaterial` inside a capsule. Keep this depth concentrated on the notebook, page, and writing tools.

## Shapes

Card, cover, page, and selected-tool radii are distinct frontmatter tokens. Notebook cards have a thin semantic separator outline. Page thumbnails use a smaller radius (4 pt). Toolbars and page navigation use capsules; ink swatches and the editor options control use circles.

## Components

**Notebook creation.** A native sheet uses a form with title, paper preview, template, and cover selection. Templates are Blank, Ruled, Grid, and Dot. Default paper starts as Ruled, persists through `defaultTemplate`, and initializes subsequent creation sheets. The default cover is Blue. An empty title becomes “Untitled notebook.” New pages inherit the current page template.

**Paper and PDF.** Native pages default to (768 × 1024 pt). Ruled, grid, and dot paper use the frontmatter paper spacing. Ruled/grid horizontal lines begin two intervals from the top; ruled paper includes a soft red margin (56 pt). Imported PDFs preserve source dimensions and rotation, with transparent editable ink above source content.

**Writing tools.** Pen, pencil, marker, eraser, and lasso use SF Symbols and a visible selected state. Ink color and stroke width, undo/redo, page navigation, and export remain accessible through the floating controls and native options menu. Loading blocks drawing until the selected page is ready.

**Structure and preferences.** A notebook is a titled cover with ordered pages and an optional folder. Folders appear when they contain a notebook. Recents applies last-modified sorting. Grid/list choice, query, sort, folder selection, and current page are session state; do not imply they survive relaunch. Appearance persists as System, Light, or Dark through `appearance`; System is the default.

**Feedback.** Preserve separate local-save and cloud-sync language. Editor states include “Saving locally…”, “Saved on this iPad”, and “Could not save — retry before closing”. Library metadata distinguishes “On this iPad”, “Waiting to sync”, and conflicts. Drive status distinguishes syncing, deferred sync while writing, retry, success, and conflicts needing review. Empty library, no search results, loading, storage failure, import failure, and save retry use native messages and controls. Conflict actions preserve versions and describe the concrete choice.

## Do's and Don'ts

- Do preserve native split navigation, semantic typography and colors, white paper, pastel covers, and the established floating controls.
- Do retain the library inset, grid gap, paper rhythm, and writing-control touch size from frontmatter.
- Do distinguish locally saved work from successfully synced work and preserve visible recovery actions.
- Don't populate real application state with reference notebook names, accounts, counts, or samples.
- Don't claim physical Pencil behavior or visual screenshot validation from compilation alone.

Documentation evidence: this record was checked against the implemented SwiftUI views and state models. All 11 tests passed; the final iPad-only build and the accessibility adjustment build succeeded. Native simulator captures from an iPad Pro 13-inch (M5) in portrait are recorded in `.impeccable/review/`: `library-light.png`, `editor-light.png`, `settings-light.png`, `library-dark-accessibility.png`, and `settings-dark-accessibility.png`. Dark captures use accessibility-large Dynamic Type. Independent capture review returned a scoped ship verdict with no material visual defect in these five captures. This does not establish hardware Pencil, live OAuth, cropped/rotated PDF alignment, other iPad sizes/orientations, or editor Dark Mode/large-text presentation.


## Universal workspace and text documents

The iPhone surface uses Operate mode. Compact width replaces the sidebar with a native bottom tab bar (Workspace, Recents, Settings) and per-section navigation stacks while rendering the same workspace component: a large Workspace title, folder cards, mixed document grid/list, search, sorting and the same + creation menu. Settings is a full tab destination rather than a lone icon. All / Text / Handwritten switches content type without separating the workspace. Folder navigation preserves the native back gesture. Regular width retains Paperly's established sidebar and notebook covers, adding a restrained document cover for text. Adaptive structure follows size class, including compact iPad windows.

Text editing uses a centered column up to 700 pt wide with 24 pt side insets, an editable semantic large title, and native multiline text inputs. Headings, list markers, checkboxes, quotes, and code give structure without wrapping each block in a card. Block menus provide formatting and reordering; keyboard controls expose formatting, insertion, undo, and dismissal. Semantic colors and Dynamic Type apply to text documents. Writing paper remains white for handwriting/PDF. Compact handwriting controls scroll within two rows, with a compact page picker in the header.

The + menu creates Text document, Handwritten notebook, imports PDF/Paperly, or creates a Folder. Local-save labels use device-neutral wording. Text supports Markdown and editable Paperly export; drawing retains PDF and Paperly export. Mac is planned, not a shipped target in this pass.


## Page navigation and motion

Page by page is the default writing presentation. Each page occupies one viewport slot at whole-page fit. Swipes snap to an adjacent slot; pinch zoom temporarily removes snapping for precise panning. Creating a page commits the prior page, activates the new one, resets fit, and scrolls to it. Continuous mode remains in Notebook options → Page view. Vertical and horizontal directions are available in both modes.

Motion explains continuity: native stack/sheet transitions establish navigation, bounded 180–240 ms workspace transitions retain orientation through filtering/sorting/grid changes, selected writing tools change emphasis in 140 ms, and programmatic page changes use UIKit’s scroll animation. There are no looping decorations or animations tied to Pencil strokes. Reduce Motion removes spatial workspace/tool/page animations and automatic text-focus scrolling uses an immediate reposition instead.


Phone branding centers the existing transparent Paperly mark (28 pt) in a 44 pt frame in the leading navigation bar of the phone Workspace root. It disappears inside folders to preserve Back navigation and is never added to iPad. Accessibility sizes use wider document-grid columns and wrapping card titles; decorative text covers simplify to the document symbol so names remain legible in their labels.


## Folder appearance and note search

Folder cards retain their shared layout and add a distinct 44 pt options control next to the folder-opening button. Folder color opens a native form with named colors, tinted folder symbols, and a checkmark; color is never the only selection cue. iPad sidebar folders use the same stored color and provide the same action in a context menu. The palette uses semantic platform colors.

Search results use a readable vertical list of notebook titles and page-level previews instead of compressing recognized text into covers. Tapping a result opens its stable page ID. Progress and retry feedback describe local recognition; no confidence or completeness is fabricated. Notebook options expose a native Searchable handwriting sheet with read-only recognized text and editable supplemental terms for missed words/symbols. Search indexing is paused while writing and never runs network OCR.


Trash is a peer destination in the phone tab bar and tablet sidebar. Folder and document menus expose a destructive Move to Trash action with a native confirmation dialog. Recovery uses explicit Restore actions, preserving folder color and document content. Empty Trash states explain recovery; creation controls are absent in Trash.


Editor autosave is silent during normal writing and typing. The notebook header shows only its title; the text editor omits routine save status from the navigation bar. Actual failures remain visible, with Retry beside text errors and the notebook's existing error alert. Background writes and close/background flushes remain unchanged.

## Mac audio notes

Mac Catalyst retains the regular-width workspace and text editor rather than stretching the phone tab interface. Text documents expose Audio notes as a labeled toolbar action. Its native sheet keeps recording, saved audio, transcription, and note generation in one task-focused list. The active recorder uses a red system state and elapsed time; all other controls retain the app’s blue tint and semantic colors.

Each saved recording shows playback, duration, date, transcript state, and the next available action. The first Whisper transcription clearly explains that a model download occurs once and inference remains local. Apple Intelligence creates native headings, paragraphs, bullets, and checklist blocks in the open document; it never presents generated text as a separate proprietary format. Busy, permission-denied, model-unavailable, empty, destructive-delete, and retry states use native progress, alerts, and confirmation controls.

On iPhone, Audio note is an optional New-menu item controlled in Settings. It opens a focused full-screen recording task with elapsed time, a live metered waveform, Cancel, and one large Stop control. After Stop, the same screen communicates local transcription, Apple Intelligence generation, and saving before transitioning directly into the newly created text document. Unsupported devices never begin recording and instead state that Audio notes currently require an iPhone with Apple Intelligence.
