import Foundation
import FoundationModels

/// A tool the API client runs, not this process.
///
/// Foundation Models executes tools itself: it decodes the model's arguments,
/// calls `call(arguments:)` and feeds the result back in the same turn. The
/// OpenAI protocol splits that turn across two HTTP requests, with the client
/// executing the tool in between. So `call` refuses by throwing `Handoff`. With
/// the session told to preserve its transcript on errors, the tool calls the
/// model decided on stay readable there, and the server returns them to the client.
struct ClientExecutedTool: Tool {
    struct Handoff: Error {}

    let name: String
    let description: String
    let parameters: GenerationSchema

    func call(arguments: GeneratedContent) async throws -> String {
        throw Handoff()
    }
}

extension ClientExecutedTool {
    /// - Parameter index: Position in the request's `tools` array, for error reporting.
    init(_ definition: ToolDefinition, index: Int) throws(APIError) {
        guard definition.type == "function" else {
            throw APIError.invalidRequest(
                "Unsupported tool type '\(definition.type)'. Only 'function' tools are supported.",
                param: "tools[\(index)].type")
        }
        let function = definition.function
        do {
            self.init(
                name: function.name,
                description: function.description ?? "",
                parameters: try JSONSchemaConverter.generationSchema(named: function.name, from: function.parameters))
        } catch {
            throw APIError(error, param: "tools[\(index)].function.parameters")
        }
    }
}
