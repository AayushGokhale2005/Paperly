#if !targetEnvironment(macCatalyst)
import ActivityKit
import Foundation

public struct AudioNoteActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Phase: String, Codable, Hashable, Sendable {
            case recording, transcribing, generating, saving, complete, failed
        }

        public var phase: Phase
        public var startedAt: Date

        public init(phase: Phase, startedAt: Date) {
            self.phase = phase
            self.startedAt = startedAt
        }

        public var title: String {
            switch phase {
            case .recording: "Recording audio"
            case .transcribing: "Transcribing locally"
            case .generating: "Creating notes"
            case .saving: "Saving audio note"
            case .complete: "Audio note ready"
            case .failed: "Audio note stopped"
            }
        }

        public var compactLabel: String {
            switch phase {
            case .recording: "REC"
            case .transcribing: "TEXT"
            case .generating: "NOTES"
            case .saving: "SAVE"
            case .complete: "DONE"
            case .failed: "STOP"
            }
        }
    }

    public var recordingID: UUID

    public init(recordingID: UUID) {
        self.recordingID = recordingID
    }
}
#endif
