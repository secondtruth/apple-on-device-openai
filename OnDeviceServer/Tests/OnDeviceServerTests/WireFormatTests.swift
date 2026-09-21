import Foundation
import Testing
import Vapor

@testable import OnDeviceServer

@Suite struct WireFormatTests {
    private func json(_ value: some Encodable) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    @Test func aMessageWithOnlyToolCallsEncodesContentAsNull() throws {
        let message = AssistantMessage(
            content: nil, toolCalls: [ToolCall(id: "call_1", function: .init(name: "f", arguments: "{}"))])
        let encoded = try json(message)
        #expect(encoded["content"] == .null)
        #expect(encoded["tool_calls"]?.arrayValue?.first?["type"] == .string("function"))
    }

    @Test func everyChunkCarriesAFinishReasonKey() throws {
        let chunk = ChatCompletionChunk(
            id: "chatcmpl-1", created: 1, model: "m", choices: [.init(delta: .init(content: "Hi"))])
        let choice = try #require(try json(chunk)["choices"]?.arrayValue?.first)
        #expect(choice["finish_reason"] == .null)
        #expect(choice["delta"]?["content"] == .string("Hi"))
        #expect(choice["delta"]?["role"] == nil)
    }

    @Test func usageReportsTheTotal() throws {
        #expect(try json(TokenUsage(promptTokens: 12, completionTokens: 5))["total_tokens"] == .number(17))
    }

    @Test func errorsUseOpenAIsEnvelopeWithExplicitNulls() throws {
        let error = try json(APIError.invalidRequest("Nope.", param: "model").envelope)["error"]
        #expect(error?["message"] == .string("Nope."))
        #expect(error?["type"] == .string("invalid_request_error"))
        #expect(error?["param"] == .string("model"))
        #expect(error?["code"] == .null)
    }

    @Test func decodingFailuresNameTheOffendingParameter() throws {
        let body = #"{"messages":[{"role":"user","content":"Hi"},{"role":"wizard","content":"x"}]}"#
        do {
            _ = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(body.utf8))
            Issue.record("expected a decoding error")
        } catch {
            let apiError = APIError(describing: error)
            #expect(apiError.status == .badRequest)
            #expect(apiError.param == "messages[1].role")
        }
    }

    @Test func aMissingMessagesArrayIsReportedByName() throws {
        do {
            _ = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(#"{"model":"apple-on-device"}"#.utf8))
            Issue.record("expected a decoding error")
        } catch {
            let apiError = APIError(describing: error)
            #expect(apiError.param == "messages")
            #expect(apiError.message.contains("messages"))
        }
    }

    @Test func unavailabilityIsAServiceErrorThatExplainsTheFix() {
        let error = APIError.modelUnavailable(ModelAvailability(.unavailable(.appleIntelligenceNotEnabled)))
        #expect(error.status == .serviceUnavailable)
        #expect(error.code == "apple_intelligence_disabled")
        #expect(error.message.contains("System Settings"))
        #expect(error.retryAfter == nil)

        let downloading = APIError.modelUnavailable(ModelAvailability(.unavailable(.modelNotReady)))
        #expect(downloading.code == "model_downloading")
        #expect(downloading.retryAfter != nil)
    }
}
