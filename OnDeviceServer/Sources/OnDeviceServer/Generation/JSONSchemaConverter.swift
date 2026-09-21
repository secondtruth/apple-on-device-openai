import Foundation
import FoundationModels

/// Converts a JSON Schema, as OpenAI clients send it for tool parameters and
/// structured output, into a Foundation Models `GenerationSchema`.
///
/// `GenerationSchema` is Codable, but only for the dialect the framework emits
/// itself (it requires `x-order`), so the conversion goes through
/// `DynamicGenerationSchema`. That type can express objects, arrays, strings,
/// numbers, booleans, null, string enums, `anyOf` and `$ref`. Everything else
/// falls into one of two groups:
///
/// - Keywords that merely narrow a value (`format`, `minLength`, `default`, …)
///   cannot be enforced during decoding. They are appended to the property's
///   description so the model still sees them as a hint.
/// - Keywords that change the shape (`allOf`, `not`, `patternProperties`,
///   free-form maps, non-string enums, …) have no representation. They are
///   rejected with the JSON path, rather than approximated.
struct JSONSchemaConverter {
    struct UnsupportedSchema: Error, Equatable {
        var path: String
        var reason: String
    }

    private let rootName: String
    private var definitions: [String: JSONValue] = [:]

    /// - Parameter name: Names the root object. The framework requires schema
    ///   names to be unique, so nested schemas derive theirs from this one.
    static func generationSchema(
        named name: String, description: String? = nil, from schema: JSONValue?
    ) throws(UnsupportedSchema) -> GenerationSchema {
        var converter = JSONSchemaConverter(rootName: name)
        return try converter.convert(schema ?? .object([:]), description: description)
    }

    private init(rootName: String) {
        self.rootName = rootName
    }

    private mutating func convert(
        _ schema: JSONValue, description: String?
    ) throws(UnsupportedSchema) -> GenerationSchema {
        guard let members = schema.objectValue else {
            throw UnsupportedSchema(path: "$", reason: "the schema must be a JSON object")
        }
        // A tool without parameters may omit `type` altogether.
        if let type = members["type"], type != .string("object") {
            throw UnsupportedSchema(path: "$.type", reason: "the root schema must have type \"object\"")
        }
        definitions = (members["$defs"] ?? members["definitions"])?.objectValue ?? [:]

        let root = try object(members, name: rootName, description: description, path: "$")
        var dependencies: [DynamicGenerationSchema] = []
        for (name, definition) in definitions.sorted(by: { $0.key < $1.key }) {
            dependencies.append(try node(definition, name: name, path: "$.$defs.\(name)"))
        }

        do {
            return try GenerationSchema(root: root, dependencies: dependencies)
        } catch {
            throw UnsupportedSchema(path: "$", reason: String(describing: error))
        }
    }

    // MARK: Nodes

    private func node(
        _ schema: JSONValue, name: String, path: String
    ) throws(UnsupportedSchema) -> DynamicGenerationSchema {
        guard let members = schema.objectValue else {
            // `true` and `{}` both mean "any value", which has no typed representation.
            throw UnsupportedSchema(path: path, reason: "boolean schemas are not supported; give the value a type")
        }
        try rejectShapeKeywords(in: members, path: path)

        if let reference = members["$ref"] {
            return try self.reference(reference, path: path)
        }
        if let choices = members["anyOf"] ?? members["oneOf"] {
            // `oneOf` is decoded as `anyOf`: the model produces one branch either way,
            // and exclusivity between branches cannot be checked while decoding.
            return try union(choices, name: name, description: members["description"]?.stringValue, path: path)
        }
        if let values = members["enum"] {
            return try enumeration(values, name: name, description: members["description"]?.stringValue, path: path)
        }
        if let constant = members["const"] {
            guard let value = constant.stringValue else {
                throw UnsupportedSchema(path: "\(path).const", reason: "only string constants are supported")
            }
            return DynamicGenerationSchema(type: String.self, guides: [.constant(value)])
        }

        switch members["type"] {
        case .string(let type):
            return try typed(type, members, name: name, path: path)
        case .array(let types):
            // The `["string", "null"]` spelling of a nullable value.
            let choices = JSONValue.array(types.map { .object(members.merging(["type": $0]) { $1 }) })
            return try union(choices, name: name, description: nil, path: path)
        default:
            throw UnsupportedSchema(path: path, reason: "the schema has no \"type\", and untyped values are not supported")
        }
    }

    private func typed(
        _ type: String, _ members: [String: JSONValue], name: String, path: String
    ) throws(UnsupportedSchema) -> DynamicGenerationSchema {
        switch type {
        case "object":
            return try object(members, name: name, description: members["description"]?.stringValue, path: path)
        case "array":
            guard let items = members["items"] else {
                throw UnsupportedSchema(path: path, reason: "arrays need an \"items\" schema")
            }
            return DynamicGenerationSchema(
                arrayOf: try node(items, name: "\(name).item", path: "\(path).items"),
                minimumElements: members["minItems"]?.integerValue,
                maximumElements: members["maxItems"]?.integerValue)
        case "string":
            return try string(members, path: path)
        case "integer":
            var guides: [GenerationGuide<Int>] = []
            if let minimum = members["minimum"]?.integerValue { guides.append(.minimum(minimum)) }
            if let maximum = members["maximum"]?.integerValue { guides.append(.maximum(maximum)) }
            return DynamicGenerationSchema(type: Int.self, guides: guides)
        case "number":
            var guides: [GenerationGuide<Double>] = []
            if let minimum = members["minimum"]?.numberValue { guides.append(.minimum(minimum)) }
            if let maximum = members["maximum"]?.numberValue { guides.append(.maximum(maximum)) }
            return DynamicGenerationSchema(type: Double.self, guides: guides)
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self)
        case "null":
            return .null
        default:
            throw UnsupportedSchema(path: "\(path).type", reason: "unknown type \"\(type)\"")
        }
    }

    private func object(
        _ members: [String: JSONValue], name: String, description: String?, path: String
    ) throws(UnsupportedSchema) -> DynamicGenerationSchema {
        if case .object = members["additionalProperties"] {
            throw UnsupportedSchema(
                path: "\(path).additionalProperties",
                reason: "free-form maps are not supported; list the properties explicitly")
        }
        let required = Set(members["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        let declared = members["properties"]?.objectValue ?? [:]

        // JSON objects are unordered once parsed. Required properties go first,
        // then alphabetically, so the prompt the model sees is stable across requests.
        let names = declared.keys.sorted { lhs, rhs in
            let (lhsRequired, rhsRequired) = (required.contains(lhs), required.contains(rhs))
            return lhsRequired == rhsRequired ? lhs < rhs : lhsRequired
        }

        var properties: [DynamicGenerationSchema.Property] = []
        for propertyName in names {
            let schema = declared[propertyName]!
            let propertyPath = "\(path).properties.\(propertyName)"
            properties.append(DynamicGenerationSchema.Property(
                name: propertyName,
                description: Self.description(of: schema),
                schema: try node(schema, name: "\(name).\(propertyName)", path: propertyPath),
                isOptional: !required.contains(propertyName)))
        }
        return DynamicGenerationSchema(name: name, description: description, properties: properties)
    }

    private func string(
        _ members: [String: JSONValue], path: String
    ) throws(UnsupportedSchema) -> DynamicGenerationSchema {
        guard let pattern = members["pattern"]?.stringValue else {
            return DynamicGenerationSchema(type: String.self)
        }
        do {
            return DynamicGenerationSchema(type: String.self, guides: [.pattern(try Regex(pattern))])
        } catch {
            throw UnsupportedSchema(path: "\(path).pattern", reason: "the pattern is not a valid regular expression")
        }
    }

    private func enumeration(
        _ values: JSONValue, name: String, description: String?, path: String
    ) throws(UnsupportedSchema) -> DynamicGenerationSchema {
        let elements = values.arrayValue ?? []
        let strings = elements.compactMap(\.stringValue)
        guard !strings.isEmpty, strings.count == elements.count else {
            throw UnsupportedSchema(path: "\(path).enum", reason: "only non-empty enums of strings are supported")
        }
        return DynamicGenerationSchema(name: name, description: description, anyOf: strings)
    }

    private func union(
        _ choices: JSONValue, name: String, description: String?, path: String
    ) throws(UnsupportedSchema) -> DynamicGenerationSchema {
        guard let elements = choices.arrayValue, !elements.isEmpty else {
            throw UnsupportedSchema(path: path, reason: "anyOf needs at least one schema")
        }
        var converted: [DynamicGenerationSchema] = []
        for (index, element) in elements.enumerated() {
            converted.append(try node(element, name: "\(name).\(index)", path: "\(path).anyOf[\(index)]"))
        }
        return converted.count == 1
            ? converted[0]
            : DynamicGenerationSchema(name: name, description: description, anyOf: converted)
    }

    private func reference(_ reference: JSONValue, path: String) throws(UnsupportedSchema) -> DynamicGenerationSchema {
        let prefixes = ["#/$defs/", "#/definitions/"]
        guard let target = reference.stringValue,
            let prefix = prefixes.first(where: target.hasPrefix),
            definitions[String(target.dropFirst(prefix.count))] != nil
        else {
            throw UnsupportedSchema(
                path: "\(path).$ref", reason: "only references into this schema's $defs are supported")
        }
        return DynamicGenerationSchema(referenceTo: String(target.dropFirst(prefix.count)))
    }

    // MARK: Keywords without a representation

    private static let shapeKeywords = [
        "allOf", "not", "if", "then", "else", "patternProperties", "propertyNames",
        "prefixItems", "contains", "dependentSchemas", "dependentRequired", "unevaluatedProperties",
    ]

    private func rejectShapeKeywords(in members: [String: JSONValue], path: String) throws(UnsupportedSchema) {
        if let keyword = Self.shapeKeywords.first(where: { members[$0] != nil }) {
            throw UnsupportedSchema(path: "\(path).\(keyword)", reason: "\"\(keyword)\" is not supported")
        }
    }

    private static let hintKeywords = [
        "format", "minLength", "maxLength", "multipleOf", "exclusiveMinimum", "exclusiveMaximum",
        "uniqueItems", "default",
    ]

    /// The property description, extended by the constraints that cannot be enforced.
    private static func description(of schema: JSONValue) -> String? {
        let hints = hintKeywords.compactMap { keyword -> String? in
            guard let value = schema[keyword], let data = try? JSONEncoder().encode(value) else { return nil }
            return "\(keyword): \(String(decoding: data, as: UTF8.self))"
        }
        let parts = [schema["description"]?.stringValue, hints.isEmpty ? nil : "(\(hints.joined(separator: ", ")))"]
        let text = parts.compactMap { $0 }.joined(separator: " ")
        return text.isEmpty ? nil : text
    }
}

extension APIError {
    init(_ error: JSONSchemaConverter.UnsupportedSchema, param: String) {
        self = .invalidRequest(
            "Unsupported JSON Schema at \(error.path): \(error.reason).",
            param: param, code: "unsupported_schema")
    }
}
