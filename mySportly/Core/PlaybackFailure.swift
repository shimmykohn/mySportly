import Foundation

/// Converts media errors into bounded, credential-free messages. CoreMedia
/// nests HTTP failures inside NSURLErrorDomain rather than returning a response.
public struct PlaybackFailure: Equatable, Sendable {
    public let httpStatus: Int?
    public init(httpStatus: Int?) { self.httpStatus = httpStatus }
    public init(error: Error?) {
        var current = error as NSError?
        var status: Int?
        for _ in 0..<8 {
            guard let error = current else { break }
            for key in ["NSDescription", NSLocalizedDescriptionKey, NSLocalizedFailureReasonErrorKey] {
                guard let description = error.userInfo[key] as? String else { continue }
                let text = String(description.prefix(2_048))
                if let range = text.range(of: #"\bHTTP(?:/\d(?:\.\d)?)?\s+(?:status(?:\s+code)?\s*[:=]?\s*)?[45]\d\d\b"#, options: [.regularExpression, .caseInsensitive]),
                   let code = Int(text[range].suffix(3)) { status = code; break }
            }
            if status != nil { break }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        httpStatus = status
    }
    public var shouldRetry: Bool {
        guard let status = httpStatus else { return true }
        if (400..<500).contains(status) { return [408, 425, 429].contains(status) }
        return status != 501 && status != 511
    }
    public var message: String {
        switch httpStatus {
        case 511:
            "The provider rejected the video request (HTTP 511). Check the connection your provider permits or contact your provider."
        case 401, 403:
            "The provider refused access to this stream (HTTP \(httpStatus!)). Check your source or subscription."
        case 404, 410:
            "This stream is unavailable from your provider (HTTP \(httpStatus!)). Choose another stream or refresh your playlist."
        case 456, 458, 460, 461, 462:
            // Non-standard codes IPTV panels use when an account is at its stream limit.
            "Your provider says this account is busy (HTTP \(httpStatus!)). It may be streaming on another device or app, or a stream just closed hasn’t been released yet. Stop other streams, wait a minute, then try again."
        case 429:
            "The provider is receiving too many requests. Wait a moment before trying again."
        case 500, 502, 503, 504:
            "The provider is temporarily unable to send this stream (HTTP \(httpStatus!)). Try again shortly."
        case let status?:
            "The provider could not send this stream (HTTP \(status)). Choose another stream or contact your provider."
        case nil:
            "The stream could not be played. Check the source, format, or connection limit."
        }
    }
}
