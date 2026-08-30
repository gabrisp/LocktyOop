import Foundation
import CoreNFC

protocol NFCServicing {
    func beginScan() async throws -> NFCAction
    func scanTagIdentifier() async throws -> String
}

enum NFCServiceError: LocalizedError {
    case unavailable
    case invalidTag

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "NFC is unavailable on this device."
        case .invalidTag:
            "The NFC tag does not contain a Lockty action."
        }
    }
}

@MainActor
final class LiveNFCService: NSObject, NFCNDEFReaderSessionDelegate, NFCServicing {
    private var session: NFCNDEFReaderSession?
    private var continuation: CheckedContinuation<NFCAction, Error>?

    func beginScan() async throws -> NFCAction {
        guard NFCNDEFReaderSession.readingAvailable else { throw NFCServiceError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
            self.session = session
            session.alertMessage = "Hold Lockty near the NFC tag."
            session.begin()
        }
    }

    func scanTagIdentifier() async throws -> String {
        try await LiveNFCTagIdentifierScanner().scan()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        self.session = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let payload = messages.first?.records.first?.locktyTextPayload else {
            continuation?.resume(throwing: NFCServiceError.invalidTag)
            continuation = nil
            return
        }

        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = NFCAction.Kind(rawValue: parts[0]) else {
            continuation?.resume(throwing: NFCServiceError.invalidTag)
            continuation = nil
            return
        }
        continuation?.resume(returning: NFCAction(tagIdentifier: payload, kind: kind, routineID: UUID(uuidString: parts[1])))
        continuation = nil
    }
}

private final class LiveNFCTagIdentifierScanner: NSObject, NFCTagReaderSessionDelegate {
    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<String, Error>?

    func scan() async throws -> String {
        guard NFCTagReaderSession.readingAvailable else { throw NFCServiceError.unavailable }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            guard let session = NFCTagReaderSession(
                pollingOption: [.iso14443, .iso15693, .iso18092],
                delegate: self,
                queue: nil
            ) else {
                self.continuation = nil
                continuation.resume(throwing: NFCServiceError.unavailable)
                return
            }
            self.session = session
            session.alertMessage = "Hold Lockty near the NFC tag."
            session.begin()
        }
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        self.session = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }

        if tags.count > 1 {
            session.alertMessage = "Use one NFC tag at a time."
            session.restartPolling()
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self else { return }

            if let error {
                self.finish(session: session, error: error)
                return
            }

            do {
                let identifier = try Self.identifier(for: tag)
                session.alertMessage = "Tag scanned."
                self.finish(session: session, identifier: identifier)
            } catch {
                self.finish(session: session, error: error)
            }
        }
    }

    private func finish(session: NFCTagReaderSession, identifier: String) {
        let continuation = continuation
        self.continuation = nil
        self.session = nil
        continuation?.resume(returning: identifier)
        session.invalidate()
    }

    private func finish(session: NFCTagReaderSession, error: Error) {
        let continuation = continuation
        self.continuation = nil
        self.session = nil
        continuation?.resume(throwing: error)
        session.invalidate(errorMessage: error.localizedDescription)
    }

    private static func identifier(for tag: NFCTag) throws -> String {
        let data: Data

        switch tag {
        case .miFare(let tag):
            data = tag.identifier
        case .iso7816(let tag):
            data = tag.identifier
        case .iso15693(let tag):
            data = tag.identifier
        case .feliCa(let tag):
            data = tag.currentIDm
        @unknown default:
            throw NFCServiceError.invalidTag
        }

        let identifier = data.map { String(format: "%02x", $0) }.joined()
        guard !identifier.isEmpty else { throw NFCServiceError.invalidTag }
        return identifier
    }
}

private extension NFCNDEFPayload {
    var locktyTextPayload: String? {
        guard type == Data([0x54]), payload.count > 1 else { return nil }
        let languageLength = Int(payload[0] & 0x3F)
        guard payload.count > languageLength + 1 else { return nil }
        return String(data: payload[(languageLength + 1)...], encoding: .utf8)
    }
}
