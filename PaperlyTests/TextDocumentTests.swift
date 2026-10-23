import XCTest
@testable import Paperly

@MainActor final class TextDocumentTests: XCTestCase {
    private func withRepository(_ operation: (NotebookRepository, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try await operation(NotebookRepository(root: root), root)
    }
    func testTextArchiveRoundTripAndInvalidContentRejection() async throws {
        try await withRepository { repo, _ in
            let m = try await repo.createText(title: "Research", folder: "Work")
            let text = TextDocument(blocks: [TextBlock(kind: .heading1, text: "Ideas"), TextBlock(kind: .checklist, text: "Try it", checked: true), TextBlock(kind: .code, text: "let value = 1")])
            let saved = try await repo.saveText(text, title: "Research", notebook: m.id)
            let archive = try await repo.exportData(m.id)
            let restored = try await repo.importArchive(archive)
            let content = try await repo.textDocument(restored.id)
            XCTAssertEqual(text, content)
            XCTAssertTrue(saved.isTextDocument); XCTAssertTrue(saved.pages.isEmpty)
            XCTAssertEqual(restored.folder, "Work"); XCTAssertNotEqual(restored.id, m.id)
            var broken = try NotebookArchive.decode(archive)
            broken.assets[saved.textFile!] = Data("not a document".utf8)
            XCTAssertThrowsError(try broken.encoded())
            broken.assets.removeAll(); XCTAssertThrowsError(try broken.encoded())
        }
    }
    func testOldHandwrittenManifestStillDecodes() throws {
        var m = NotebookManifest(title: "Existing notes"); m.formatVersion = 2
        let data = try JSONEncoder().encode(m)
        let restored = try JSONDecoder().decode(NotebookManifest.self, from: data)
        try restored.validate(); XCTAssertFalse(restored.isTextDocument)
        var invalid = m; invalid.textFile = "text/\(UUID()).json"; invalid.pages = []
        XCTAssertThrowsError(try invalid.validate())
    }
    func testMixedWorkspaceFiltersAndFolders() async throws {
        try await withRepository { repo, _ in
            let text = try await repo.createText(title: "Plan", folder: "School")
            let ink = try await repo.create(title: "Lecture", template: .ruled, cover: "blue", folder: "School")
            let model = LibraryViewModel(repository: repo)
            await model.reload(); model.folder = "School"
            XCTAssertEqual(Set(model.filtered.map(\.id)), [text.id, ink.id])
            model.contentFilter = .text; XCTAssertEqual(model.filtered.map(\.id), [text.id])
            model.contentFilter = .handwriting; XCTAssertEqual(model.filtered.map(\.id), [ink.id])
            model.contentFilter = .all; model.query = "plan"; XCTAssertEqual(model.filtered.map(\.id), [text.id])
        }
    }
    func testAutosaveFlushReopenAndGenerationDoNotLoseLaterEdit() async throws {
        try await withRepository { repo, root in
            let m = try await repo.createText(title: "Draft")
            let vm = TextDocumentViewModel(manifest: m, repository: repo)
            await vm.load()
            let id = vm.content.blocks[0].id
            vm.setText(id, "First")
            let saving = Task { await vm.flush() }
            await Task.yield()
            vm.setText(id, "Final revision 👩🏽‍💻")
            vm.setTitle("Updated title")
            _ = await saving.value
            let ok = await vm.flush(); XCTAssertTrue(ok); XCTAssertFalse(vm.dirty)
            let reopened = try NotebookRepository(root: root)
            let disk = try await reopened.textDocument(m.id)
            let manifest = try await reopened.load(m.id)
            XCTAssertEqual(disk.blocks[0].text, "Final revision 👩🏽‍💻")
            XCTAssertEqual(manifest.title, "Updated title"); XCTAssertNotEqual(manifest.generation, m.generation)
            let oldPath = root.appendingPathComponent(m.id.uuidString + ".paperly").appendingPathComponent(m.textFile!)
            XCTAssertFalse(FileManager.default.fileExists(atPath: oldPath.path))
        }
    }
    func testSplitAtUTF16ContinuesListsAndEmptyReturnExitsList() async throws {
        try await withRepository { repo, _ in
            let m = try await repo.createText(title: "Lists")
            let vm = TextDocumentViewModel(manifest: m, repository: repo); await vm.load()
            let id = vm.content.blocks[0].id
            vm.setKind(id, .checklist); vm.setText(id, "Hello 🌍 world"); vm.toggle(id)
            vm.split(id, atUTF16: 8)
            XCTAssertEqual(vm.content.blocks[0].text, "Hello 🌍")
            XCTAssertEqual(vm.content.blocks[1].text, " world")
            XCTAssertEqual(vm.content.blocks[1].kind, .checklist); XCTAssertFalse(vm.content.blocks[1].checked)
            let next = vm.content.blocks[1].id
            vm.setText(next, ""); vm.split(next, atUTF16: 0)
            XCTAssertEqual(vm.content.blocks.count, 2); XCTAssertEqual(vm.content.blocks[1].kind, .paragraph)
            _ = await vm.flush()
        }
    }
    func testBlockReorderDeleteUndoRedoKeepsIdentity() async throws {
        try await withRepository { repo, _ in
            let m = try await repo.createText(title: "Blocks")
            let vm = TextDocumentViewModel(manifest: m, repository: repo); await vm.load()
            let first = vm.content.blocks[0].id
            vm.setText(first, "One"); let second = vm.insert(after: first, kind: .heading1); vm.setText(second, "Two")
            vm.move(second, by: -1); XCTAssertEqual(vm.content.blocks.map(\.id), [second, first])
            vm.delete(first); XCTAssertEqual(vm.content.blocks.count, 1)
            vm.undo(); XCTAssertEqual(vm.content.blocks.map(\.id), [second, first])
            vm.redo(); XCTAssertEqual(vm.content.blocks.map(\.id), [second])
            vm.delete(second); XCTAssertEqual(vm.content.blocks.count, 1); XCTAssertEqual(vm.content.blocks[0].text, "")
            _ = await vm.flush()
        }
    }
    func testFailedSaveRetainsDirtyContentForRetry() async throws {
        try await withRepository { repo, root in
            let m = try await repo.createText(title: "Recovery")
            let vm = TextDocumentViewModel(manifest: m, repository: repo); await vm.load()
            vm.setText(vm.content.blocks[0].id, "Keep this")
            let dir = root.appendingPathComponent(m.id.uuidString + ".paperly")
            let parked = root.appendingPathComponent("parked")
            try FileManager.default.moveItem(at: dir, to: parked)
            let failed = await vm.flush(); XCTAssertFalse(failed); XCTAssertTrue(vm.dirty); XCTAssertNotNil(vm.error)
            try FileManager.default.moveItem(at: parked, to: dir)
            let retried = await vm.flush(); XCTAssertTrue(retried); XCTAssertFalse(vm.dirty); XCTAssertNil(vm.error)
            let disk = try await repo.textDocument(m.id); XCTAssertEqual(disk.blocks[0].text, "Keep this")
        }
    }
    func testMarkdownPreservesChecksNumberingAndCodeFence() throws {
        let text = TextDocument(blocks: [.init(kind: .heading1, text: "Plan"), .init(kind: .numbered, text: "First"), .init(kind: .numbered, text: "Second"), .init(kind: .checklist, text: "Done", checked: true), .init(kind: .code, text: "```swift\nprint(1)\n```")])
        let markdown = text.markdown(title: "Title")
        XCTAssertTrue(markdown.contains("2. Second")); XCTAssertTrue(markdown.contains("- [x] Done")); XCTAssertTrue(markdown.contains("````\n```swift"))
        var invalid = text; invalid.blocks.append(invalid.blocks[0]); XCTAssertThrowsError(try invalid.encoded())
    }
}

extension TextDocumentTests {
    func testRecordingTranscriptNotesAndExportLifecycle() async throws {
        try await withRepository { repo, _ in
            let manifest = try await repo.createText(title: "Meeting")
            let recording = try await repo.addRecording(
                Data([1, 2, 3, 4]),
                title: "Stand-up",
                duration: 12,
                notebook: manifest.id
            )
            let initialRecordings = try await repo.recordings(manifest.id)
            XCTAssertEqual(initialRecordings.map(\.id), [recording.id])
            let audioURL = try await repo.recordingURL(recording.id, notebook: manifest.id)
            XCTAssertEqual(try Data(contentsOf: audioURL), Data([1, 2, 3, 4]))

            let transcript = RecordingTranscript(text: "We shipped it.", segments: [.init(start: 0, end: 2, text: "We shipped it.")])
            let updated = try await repo.saveTranscript(transcript, recording: recording.id, notebook: manifest.id)
            XCTAssertNotNil(updated.transcriptFile)
            let savedTranscript = try await repo.transcript(recording: recording.id, notebook: manifest.id)
            XCTAssertEqual(savedTranscript, transcript)
            try await repo.markNotesAdded(recording: recording.id, notebook: manifest.id)
            let markedRecordings = try await repo.recordings(manifest.id)
            XCTAssertNotNil(markedRecordings.first?.notesAddedAt)

            let exported = try await repo.exportData(manifest.id)
            let imported = try await repo.importArchive(exported)
            let importedRecordings = try await repo.recordings(imported.id)
            XCTAssertEqual(importedRecordings.count, 1)
            try await repo.deleteRecording(recording.id, notebook: manifest.id)
            let finalRecordings = try await repo.recordings(manifest.id)
            XCTAssertTrue(finalRecordings.isEmpty)
        }
    }
}
