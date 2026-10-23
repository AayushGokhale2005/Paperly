import XCTest
@testable import PaperlyCore

final class RecordingTests: XCTestCase {
    func testRecordingArchiveRoundTrip() throws {
        let recordingID = UUID()
        let audio = "assets/audio/\(recordingID).m4a"
        let transcriptPath = "assets/transcripts/\(recordingID).json"
        let transcript = RecordingTranscript(
            text: "A short meeting",
            segments: [.init(start: 0, end: 2, text: "A short meeting")]
        )
        var manifest = NotebookManifest(title: "Meeting")
        manifest.pages = []
        manifest.textFile = "text/\(UUID()).json"
        manifest.formatVersion = 6
        var recording = NotebookRecording(id: recordingID, title: "Recording", duration: 2, audioFile: audio)
        recording.transcriptFile = transcriptPath
        manifest.recordings = [recording]
        let archive = NotebookArchive(manifest: manifest, assets: [
            manifest.textFile!: try TextDocument().encoded(),
            audio: Data([1, 2, 3]),
            transcriptPath: try JSONEncoder().encode(transcript)
        ])

        XCTAssertEqual(try NotebookArchive.decode(archive.encoded()).manifest.recordingItems, [recording])
    }

    func testRecordingRejectsUnsafeOrMismatchedAssets() {
        XCTAssertThrowsError(try NotebookRecording(
            title: "Bad",
            duration: 1,
            audioFile: "../escape.m4a"
        ).validate())
        XCTAssertThrowsError(try NotebookRecording(
            title: "Bad",
            duration: 1,
            audioFile: "assets/images/\(UUID()).m4a"
        ).validate())
    }

    func testTranscriptChunksPreserveWordsAndUnicode() {
        let input = Array(repeating: "one two three 📝 four five six", count: 30).joined(separator: " ")
        let chunks = TranscriptChunks.split(input, maximumBytes: 256)
        XCTAssertEqual(chunks.joined(separator: " "), input)
        XCTAssertTrue(chunks.allSatisfy { $0.utf8.count <= 256 })
    }

    func testGeneratedMarkdownBecomesNativeBlocks() {
        let blocks = GeneratedNoteBlocks.parse("""
            # Meeting notes
            ## Summary
            Shipped the first version.
            ## Action items
            - [ ] Test on Mac
            - Keep the local model
            """)
        XCTAssertEqual(blocks.map(\.kind), [.heading1, .heading2, .paragraph, .heading2, .checklist, .bullet])
        XCTAssertEqual(blocks[4].text, "Test on Mac")
    }
}
