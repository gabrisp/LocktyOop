import Foundation
import CoreNFC

protocol NFCServicing {
    func beginScan() async throws -> NFCAction
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

struct MockNFCService: NFCServicing {
    func beginScan() async throws -> NFCAction {
        throw NFCServiceError.unavailable
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

private extension NFCNDEFPayload {
    var locktyTextPayload: String? {
        guard type == Data([0x54]), payload.count > 1 else { return nil }
        let languageLength = Int(payload[0] & 0x3F)
        guard payload.count > languageLength + 1 else { return nil }
        return String(data: payload[(languageLength + 1)...], encoding: .utf8)
    }
}
