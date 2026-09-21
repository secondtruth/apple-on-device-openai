import Vapor

/// Writes a `text/event-stream` body in the framing OpenAI clients parse:
/// one `data:` line per event, a blank line after each, `[DONE]` as the last.
struct ServerSentEventWriter: Sendable {
    let body: any AsyncBodyStreamWriter

    static let headers: HTTPHeaders = [
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        // Reverse proxies buffer responses by default, which turns a stream into
        // one late block. nginx honours this header; others at least ignore it.
        "X-Accel-Buffering": "no",
    ]

    /// Throws when the client has gone away: a write to a closed connection fails.
    func send(_ event: some Encodable) async throws {
        // JSONEncoder never emits a raw newline, so the payload stays on one `data:` line.
        var buffer = ByteBuffer(string: "data: ")
        buffer.writeBytes(try JSONEncoder().encode(event))
        buffer.writeString("\n\n")
        try await body.write(.buffer(buffer))
    }

    func sendDone() async throws {
        try await body.write(.buffer(ByteBuffer(string: "data: [DONE]\n\n")))
    }
}
