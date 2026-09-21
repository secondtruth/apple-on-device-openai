import Foundation
import FoundationModels
import Testing

@testable import OnDeviceServer

@Suite struct ConversationTests {
    private func messages(_ json: String) throws -> [ChatMessage] {
        try JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
    }

    private func kinds(_ transcript: Transcript) -> [String] {
        transcript.map { entry in
            switch entry {
            case .instructions: "instructions"
            case .prompt: "prompt"
            case .toolCalls: "toolCalls"
            case .toolOutput: "toolOutput"
            case .response: "response"
            case .reasoning: "reasoning"
            @unknown default: "unknown"
            }
        }
    }

    @Test func theLastUserMessageBecomesThePromptAndTheRestHistory() throws {
        let conversation = try Conversation(
            messages: messages(
                """
                [{"role":"system","content":"Be brief."},
                 {"role":"user","content":"Hi"},
                 {"role":"assistant","content":"Hello!"},
                 {"role":"user","content":[{"type":"text","text":"How are"},{"type":"text","text":"you?"}]}]
                """))

        #expect(kinds(conversation.transcript) == ["instructions", "prompt", "response"])
        #expect(conversation.prompt == "How are\nyou?")
    }

    @Test func systemMessagesAreGatheredIntoOneLeadingInstructionsEntry() throws {
        let conversation = try Conversation(
            messages: messages(
                """
                [{"role":"system","content":"One."},{"role":"user","content":"Hi"},
                 {"role":"assistant","content":"Hello"},{"role":"developer","content":"Two."},
                 {"role":"user","content":"Go"}]
                """))

        #expect(kinds(conversation.transcript) == ["instructions", "prompt", "response"])
        guard case .instructions(let instructions) = conversation.transcript.first,
            case .text(let segment) = instructions.segments.first
        else {
            Issue.record("expected a leading instructions entry with text")
            return
        }
        #expect(segment.content == "One.\n\nTwo.")
    }

    @Test(arguments: [
        (#"[]"#, "messages"),
        (#"[{"role":"user","content":"Hi"},{"role":"assistant","content":"Hello"}]"#, "messages[1].role"),
        (#"[{"role":"user","content":[{"type":"image_url","image_url":{"url":"data:x"}}]}]"#, "messages[0].content[0]"),
    ])
    func rejectsMalformedConversations(json: String, param: String) throws {
        let decoded = try messages(json)
        let error = #expect(throws: APIError.self) {
            try Conversation(messages: decoded)
        }
        #expect(error?.param == param)
        #expect(error?.status == .badRequest)
    }
}
