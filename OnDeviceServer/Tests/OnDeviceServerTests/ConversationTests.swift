import Foundation
import FoundationModels
import Testing

@testable import OnDeviceServer

@Suite struct ConversationTests {
    private func messages(_ json: String) throws -> [ChatMessage] {
        try JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
    }

    private func weatherTool() throws -> ClientExecutedTool {
        try ClientExecutedTool(
            ToolDefinition(type: "function", function: .init(name: "get_weather", description: "Weather", parameters: nil)),
            index: 0)
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
                """), tools: [])

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
                """), tools: [])

        #expect(kinds(conversation.transcript) == ["instructions", "prompt", "response"])
        guard case .instructions(let instructions) = conversation.transcript.first,
            case .text(let segment) = instructions.segments.first
        else {
            Issue.record("expected a leading instructions entry with text")
            return
        }
        #expect(segment.content == "One.\n\nTwo.")
    }

    @Test func toolDefinitionsCreateAnInstructionsEntryEvenWithoutSystemMessage() throws {
        let conversation = try Conversation(
            messages: messages(#"[{"role":"user","content":"Weather?"}]"#), tools: [weatherTool()])

        guard case .instructions(let instructions) = conversation.transcript.first else {
            Issue.record("expected an instructions entry")
            return
        }
        #expect(instructions.toolDefinitions.map(\.name) == ["get_weather"])
    }

    @Test func aRequestEndingInToolResultsHasNoPrompt() throws {
        let conversation = try Conversation(
            messages: messages(
                """
                [{"role":"user","content":"Weather in Berlin?"},
                 {"role":"assistant","content":null,"tool_calls":[
                    {"id":"call_1","type":"function","function":{"name":"get_weather","arguments":"{\\"city\\":\\"Berlin\\"}"}}]},
                 {"role":"tool","tool_call_id":"call_1","content":"7 degrees"}]
                """), tools: [weatherTool()])

        #expect(kinds(conversation.transcript) == ["instructions", "prompt", "toolCalls", "toolOutput"])
        #expect(conversation.prompt == nil)

        guard case .toolCalls(let calls) = conversation.transcript[2],
            case .toolOutput(let output) = conversation.transcript[3]
        else {
            Issue.record("expected tool calls followed by tool output")
            return
        }
        #expect(calls.first?.id == "call_1")
        #expect(try calls.first?.arguments.value(String.self, forProperty: "city") == "Berlin")
        #expect(output.id == "call_1")
        #expect(output.toolName == "get_weather")
    }

    @Test(arguments: [
        (#"[]"#, "messages"),
        (#"[{"role":"user","content":"Hi"},{"role":"assistant","content":"Hello"}]"#, "messages[1].role"),
        (#"[{"role":"user","content":[{"type":"image_url","image_url":{"url":"data:x"}}]}]"#, "messages[0].content[0]"),
        (#"[{"role":"tool","tool_call_id":"nope","content":"x"}]"#, "messages[0].tool_call_id"),
        (#"[{"role":"tool","content":"x"}]"#, "messages[0].tool_call_id"),
        (
            #"[{"role":"assistant","tool_calls":[{"id":"c","type":"function","function":{"name":"f","arguments":"not json"}}]},{"role":"user","content":"x"}]"#,
            "messages[0].tool_calls[0].function.arguments"
        ),
    ])
    func rejectsMalformedConversations(json: String, param: String) throws {
        let decoded = try messages(json)
        let error = #expect(throws: APIError.self) {
            try Conversation(messages: decoded, tools: [])
        }
        #expect(error?.param == param)
        #expect(error?.status == .badRequest)
    }
}
