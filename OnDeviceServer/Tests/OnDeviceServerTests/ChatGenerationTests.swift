import Foundation
import Testing

@testable import OnDeviceServer

@Suite struct ChatGenerationTests {
    private func request(_ fields: String) throws -> ChatCompletionRequest {
        let json = #"{"messages":[{"role":"user","content":"Hi"}]"# + (fields.isEmpty ? "" : ",") + fields + "}"
        return try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    }

    private static let tools =
        #""tools":[{"type":"function","function":{"name":"get_weather","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}]"#

    @Test func acceptsAPlainRequestAndDefaultsTheModel() throws {
        #expect(try ChatGeneration(request("")).model.id == OnDeviceModel.general.id)
    }

    @Test func acceptsEveryToolChoiceForm() throws {
        for choice in [#""auto""#, #""none""#, #""required""#, #"{"type":"function","function":{"name":"get_weather"}}"#] {
            _ = try ChatGeneration(request(Self.tools + #","tool_choice":"# + choice))
        }
    }

    @Test(arguments: [
        (#""model":"gpt-4o""#, "model", 404),
        (#""n":2"#, "n", 400),
        (#""stop":["END"]"#, "stop", 400),
        (#""temperature":3"#, "temperature", 400),
        (#""top_p":0"#, "top_p", 400),
        (#""max_tokens":0"#, "max_completion_tokens", 400),
        (#""tool_choice":"required""#, "tool_choice", 400),
        (tools + #","tool_choice":{"type":"function","function":{"name":"other"}}"#, "tool_choice", 400),
        (#""tools":[{"type":"retrieval","function":{"name":"x"}}]"#, "tools[0].type", 400),
        (#""tools":[{"type":"function","function":{"name":"x","parameters":{"type":"object","properties":{"a":{"not":{}}}}}}]"#,
            "tools[0].function.parameters", 400),
        (#""response_format":{"type":"json_object"}"#, "response_format.type", 400),
    ])
    func rejectsWhatTheModelCannotHonour(fields: String, param: String, status: Int) throws {
        let decoded = try request(fields)
        let error = #expect(throws: APIError.self) { try ChatGeneration(decoded) }
        #expect(error?.param == param)
        #expect(error?.status.code == UInt(status))
    }

    @Test func ignoresParametersThatDoNotChangeTheResultShape() throws {
        _ = try ChatGeneration(request(#""stop":null,"n":1,"presence_penalty":0.5,"user":"me","logit_bias":{}"#))
    }
}
