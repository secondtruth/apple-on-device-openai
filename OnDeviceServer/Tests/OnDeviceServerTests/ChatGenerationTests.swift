import Foundation
import Testing

@testable import OnDeviceServer

@Suite struct ChatGenerationTests {
    private func request(_ fields: String) throws -> ChatCompletionRequest {
        let json = #"{"messages":[{"role":"user","content":"Hi"}]"# + (fields.isEmpty ? "" : ",") + fields + "}"
        return try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    }

    @Test func acceptsAPlainRequestAndDefaultsTheModel() throws {
        #expect(try ChatGeneration(request("")).model.id == OnDeviceModel.general.id)
    }

    @Test(arguments: [
        (#""model":"gpt-4o""#, "model", 404),
        (#""n":2"#, "n", 400),
        (#""stop":["END"]"#, "stop", 400),
        (#""temperature":3"#, "temperature", 400),
        (#""top_p":0"#, "top_p", 400),
        (#""max_tokens":0"#, "max_completion_tokens", 400),
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
