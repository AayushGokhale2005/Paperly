# Goodnotes interaction observations and Paperly reconstruction

Target: installed `/Applications/Goodnotes.app`, Goodnotes 7.1.30. Observed through native accessibility and screenshots using CUA on 2026-10-22. These are interaction observations, not native decompiler output or REA Evidence IDs. See STATIC_FINDINGS.md for the separately retained REA resource records. Only a newly created `Paperly Feature Study` notebook and the project-owned Paperly logo were used as test content. No Goodnotes private data format or code was copied.

## Pen options — observed

Writing opens contextual pen/pencil/highlighter controls with three width presets and color slots. Selecting Pen again opens a panel offering Fountain Pen, Ball Pen, and Brush Pen. The inspected Fountain panel showed tip sharpness 50%, pressure sensitivity 50%, round tip flatness, and stabilization 0%. Its Pen Settings nested menu exposed speed-based thickness, latency, Draw and Hold, and Pen Gestures. These values describe this inspected installation, not universal defaults.

Paperly implements three native PencilKit profiles: fountainPen, monoline (Ball), and pen (Brush), configurable width and color, width presets, and a preview. Width, profile and scribble preferences persist. Goodnotes' custom pressure/latency/stabilization engine was not recovered. Paperly intentionally does not present unsupported pressure, tip or stabilization sliders as if they controlled PencilKit's private rendering engine.

## Scribble to Erase — settings observed; algorithm unknown

The installed Pen Gestures panel exposed Scribble to Erase, Erase Shapes and Highlighter, and Circle to Lasso. All three appeared enabled in this installation. Circle selection is outside this requested implementation scope. Gesture recognition thresholds and runtime erasure accuracy were not established by inspecting the settings. The available computer-use drag API does not provide a continuous multipoint zigzag suitable for measuring Goodnotes' classifier.

Paperly uses an independent deterministic geometric recognizer, covered by synthetic and PencilKit integration tests: bounded stroke size/time, sufficient backtracking density, and prominent direction reversals. It runs after a completed Pen stroke, only erases actual overlapping eligible ink, ignores PDF/image objects, and protects highlighter by default unless enabled. Scribbling empty space remains ink. One shared undo action restores the previous content. This is a behavioral reconstruction, not the recovered Goodnotes classifier. Conservative thresholds need physical-iPad tuning.

## Images — insertion and selection observed

The Image tool opens an Images panel with an `Insert from...` menu containing Photos and Files. Selecting the project-owned PNG through Files inserted an image into the notebook and selected it with corner resize handles and a rotation handle. Its object menu included Cut, Copy, Duplicate, Paste, Paste and Match Style, Lock, layering, crop and deletion actions.

Paperly supports selected-photo access via PhotosPicker, Files, and image paste; independent editable image objects with move/resize/rotation, duplicate/cut/copy/delete; and local persistence/export. Images render above original PDF content and below editable ink. Image editing temporarily disables canvas input so dragging an object cannot draw an accidental stroke. Crop, lock, arbitrary layer reordering and Goodnotes' Element system are not implemented in this change.

## Clipboard — affordances observed; encoding not recovered

The image object menu contains standard clipboard actions. A copy/paste attempt did not establish a trustworthy image payload round-trip: it pasted text from the existing clipboard instead. Consequently this investigation does not claim Goodnotes image clipboard serialization or cross-app format compatibility was verified. No private clipboard payload was extracted or implemented.

Paperly uses its own versioned `app.paperly.image-selection` payload with a public PNG fallback. Native PencilKit lasso commands are dispatched through UIKit’s active responder chain. In the Paperly simulator check, Select All followed by toolbar Copy/Paste produced an additional native ink stroke; Undo removed it. This establishes a bounded same-app ink copy/paste check, not cross-app compatibility. Clipboard contents are read only after a user Paste action; image import accepts bounded, validated image data. Shared ink/image history supplies toolbar and keyboard undo/redo.

## Sources and evidence limits

- Retained local REA resource records and exact resource keys: STATIC_FINDINGS.md and static-evidence/.
- [Goodnotes Pen tool documentation](https://support.goodnotes.com/hc/en-us/articles/7353756785679-Write-and-customize-ink-with-the-Pen-tool) corroborates the three profiles and configurable controls.
- [Goodnotes Scribble to Erase documentation](https://support.goodnotes.com/hc/en-us/articles/7443501398671-Erase-Handwriting-With-Scribble-to-Erase) describes covering ink and preserving marks outside the scribbled region.

No Hopper, Ghidra or IDA provider was configured; native algorithms were not decompiled. REA's CLI resource tools were used without modifying Codex MCP configuration. The skill was installed from the requested repository; the npm CLI release is 6.7.0, whose bundled skill version differs from repository main. Only commands actually supported by that CLI were used.
