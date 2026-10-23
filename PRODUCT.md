# Paperly
<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack
Swift 6, SwiftUI and UIKit, PencilKit, PDFKit, GRDB SQLite, FileManager, Google Sign-In, Drive REST v3, WhisperKit, and Apple Foundation Models. Universal iOS/iPadOS 17+ app with Mac Catalyst support; no server, Firebase, cloud AI, or analytics. Vision handwriting recognition, Whisper transcription, and Apple Intelligence note generation run on-device.

## Product Purpose
Offline-first block text documents, handwritten multi-page notebooks, PDF annotation, and Mac audio notes. One Paperly workspace supports text and ink across iPhone, iPad, and Mac. On Mac, saved recordings can be transcribed locally and converted into native document blocks. Editable PencilKit strokes, recordings, transcripts, and generated blocks remain portable and recoverable independently of Google connectivity.

## Operating Context
Typing on iPhone, iPad, or Mac; Apple Pencil or finger input for handwriting; and microphone recording on Mac. Create, organize, write, record, import/export, then optionally connect a Google account for sync.

## Brand Commitments
User-supplied Goodnotes-inspired references: quiet pale sidebar, blue selection, tactile pastel notebook covers, white paper, floating writing controls. Reference images are design evidence, not actual user notebook/account data.

## Capabilities and Constraints
Local writes precede sync. Conflicting edits must be preserved. OAuth credentials and signing team must be supplied by the developer. Hardware Pencil latency and palm rejection require physical iPad validation.

## Open Decisions
Audience beyond people taking handwritten notes is unspecified. No fabricated account data, usage, or notebook counts.

## App Icon
User-supplied folded blue paper P mark, with the white tile and surrounding background removed. Transparent master: `Artwork/PaperlyMark.png`; reference: `Artwork/IconReference.png`. Standard app-icon asset uses a deep navy backing.
