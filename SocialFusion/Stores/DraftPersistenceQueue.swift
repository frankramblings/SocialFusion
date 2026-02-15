import Foundation
import os.log

actor DraftPersistenceQueue {
    private struct PersistPayload {
        let drafts: [DraftPost]
        let destinationURL: URL
    }

    private var pendingPayload: PersistPayload?
    private var isDrainingQueue = false
    private let logger = Logger(subsystem: "com.socialfusion", category: "DraftPersistence")

    func encodeDraftPosts(from snapshots: [ThreadPostSnapshot]) -> [ThreadPostDraft] {
        snapshots.map { snapshot in
            ThreadPostDraft(
                text: snapshot.text,
                mediaData: snapshot.images.compactMap { $0.image.jpegData(compressionQuality: 0.8) },
                cwEnabled: snapshot.cwEnabled,
                cwText: snapshot.cwText,
                attachmentAltTexts: snapshot.attachmentAltTexts,
                attachmentSensitiveFlags: snapshot.attachmentSensitiveFlags
            )
        }
    }

    func enqueuePersist(drafts: [DraftPost], destinationURL: URL) {
        pendingPayload = PersistPayload(drafts: drafts, destinationURL: destinationURL)
        guard !isDrainingQueue else { return }
        isDrainingQueue = true

        Task {
            await drainPersistQueue()
        }
    }

    private func drainPersistQueue() async {
        while true {
            guard let payload = pendingPayload else {
                isDrainingQueue = false
                return
            }
            pendingPayload = nil

            // Coalesce rapid consecutive draft saves from typing/attachment changes.
            try? await Task.sleep(nanoseconds: 120_000_000)
            if pendingPayload != nil {
                continue
            }

            do {
                let data = try JSONEncoder().encode(payload.drafts)
                try data.write(to: payload.destinationURL, options: [.atomic, .completeFileProtection])
            } catch {
                logger.error("persist_drafts_failed error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
