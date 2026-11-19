import Foundation
import Testing
@testable import SportlyCore

@Suite struct PlaybackFailureTests {
    @Test func nestedProviderRejectionStopsRetriesWithoutLeakingAddresses() {
        let underlying = NSError(domain: "CoreMediaErrorDomain", code: -16846, userInfo: ["NSDescription": "HTTP 511: (unhandled)", NSURLErrorFailingURLStringErrorKey: "https://example.invalid/private-token"])
        let error = NSError(domain: NSURLErrorDomain, code: -1008, userInfo: [NSUnderlyingErrorKey: underlying])
        let failure = PlaybackFailure(error: error)
        #expect(failure.httpStatus == 511)
        #expect(!failure.shouldRetry)
        #expect(failure.message.contains("provider rejected"))
        #expect(!failure.message.contains("example.invalid"))
        #expect(!failure.message.contains("private-token"))
    }
    @Test func missingStreamsStopWhileTransientFailuresRemainRetryable() {
        for code in [401, 403, 404, 410, 511] {
            let failure = PlaybackFailure(error: NSError(domain: "CoreMediaErrorDomain", code: -1, userInfo: ["NSDescription": "HTTP \(code): error"]))
            #expect(!failure.shouldRetry)
        }
        for code in [408, 429, 500, 502, 503, 504] {
            #expect(PlaybackFailure(error: NSError(domain: "CoreMediaErrorDomain", code: -1, userInfo: ["NSDescription": "HTTP/1.1 \(code)"])).shouldRetry)
        }
        #expect(PlaybackFailure(error: URLError(.timedOut)).shouldRetry)
        #expect(PlaybackFailure(error: nil).httpStatus == nil)
    }
    @Test func streamLimitCodesSayTheAccountIsBusy() {
        let failure = PlaybackFailure(error: NSError(domain: "CoreMediaErrorDomain", code: -1, userInfo: ["NSDescription": "HTTP 460: error"]))
        #expect(failure.httpStatus == 460)
        #expect(failure.message.contains("busy"))
        #expect(!failure.shouldRetry, "Retrying at once would only hit the limit again")
    }
}
