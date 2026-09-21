import Foundation
import FoundationModels
import Testing

@testable import OnDeviceServer

@Suite struct JSONSchemaConverterTests {
    private func convert(_ json: String, named name: String = "tool") throws -> [String: JSONValue] {
        let schema = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let converted = try JSONSchemaConverter.generationSchema(named: name, from: schema)
        // The framework's own JSON rendering is the observable result of a conversion.
        let emitted = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(converted))
        return try #require(emitted.objectValue)
    }

    private func rejection(_ json: String) throws -> JSONSchemaConverter.UnsupportedSchema {
        let schema = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let error = #expect(throws: JSONSchemaConverter.UnsupportedSchema.self) {
            try JSONSchemaConverter.generationSchema(named: "tool", from: schema)
        }
        return try #require(error)
    }

    @Test func convertsPrimitivePropertiesAndRequiredness() throws {
        let emitted = try convert(
            """
            {"type":"object","properties":{
              "city":{"type":"string","description":"City name"},
              "days":{"type":"integer","minimum":1,"maximum":7},
              "precise":{"type":"boolean"},
              "radius":{"type":"number"}},
             "required":["city"]}
            """, named: "get_weather")

        #expect(emitted["title"] == .string("get_weather"))
        #expect(emitted["required"] == .array([.string("city")]))
        let properties = try #require(emitted["properties"]?.objectValue)
        #expect(properties["city"]?["type"] == .string("string"))
        #expect(properties["city"]?["description"] == .string("City name"))
        #expect(properties["days"]?["type"] == .string("integer"))
        #expect(properties["days"]?["minimum"] == .number(1))
        #expect(properties["days"]?["maximum"] == .number(7))
        #expect(properties["precise"]?["type"] == .string("boolean"))
        #expect(properties["radius"]?["type"] == .string("number"))
    }

    @Test func ordersRequiredPropertiesFirstThenAlphabetically() throws {
        let emitted = try convert(
            #"{"type":"object","properties":{"b":{"type":"string"},"a":{"type":"string"},"z":{"type":"string"}},"required":["z"]}"#)
        #expect(emitted["x-order"] == .array([.string("z"), .string("a"), .string("b")]))
    }

    @Test func convertsStringEnumsArraysAndNestedObjects() throws {
        let emitted = try convert(
            """
            {"type":"object","properties":{
              "unit":{"type":"string","enum":["celsius","fahrenheit"]},
              "tags":{"type":"array","items":{"type":"string"},"minItems":1,"maxItems":3},
              "location":{"type":"object","properties":{"lat":{"type":"number"},"lon":{"type":"number"}},"required":["lat","lon"]}},
             "required":["unit","tags","location"]}
            """)
        let properties = try #require(emitted["properties"]?.objectValue)
        #expect(properties["unit"]?["enum"] == .array([.string("celsius"), .string("fahrenheit")]))
        #expect(properties["tags"]?["minItems"] == .number(1))
        #expect(properties["tags"]?["maxItems"] == .number(3))
        #expect(properties["tags"]?["items"]?["type"] == .string("string"))
    }

    @Test func acceptsAToolWithoutParameters() throws {
        #expect(try convert("{}")["type"] == .string("object"))
        #expect(try convert(#"{"type":"object","properties":{}}"#)["type"] == .string("object"))
        _ = try JSONSchemaConverter.generationSchema(named: "ping", from: nil)
    }

    @Test func resolvesReferencesIntoDefs() throws {
        _ = try convert(
            """
            {"type":"object","properties":{"from":{"$ref":"#/$defs/Point"},"to":{"$ref":"#/$defs/Point"}},
             "required":["from","to"],
             "$defs":{"Point":{"type":"object","properties":{"x":{"type":"number"},"y":{"type":"number"}},"required":["x","y"]}}}
            """)
    }

    @Test func convertsUnionsAndNullableTypes() throws {
        _ = try convert(
            """
            {"type":"object","properties":{
              "id":{"anyOf":[{"type":"string"},{"type":"integer"}]},
              "note":{"type":["string","null"]}},
             "required":["id","note"]}
            """)
    }

    @Test func foldsUnenforceableConstraintsIntoTheDescription() throws {
        let emitted = try convert(
            #"{"type":"object","properties":{"when":{"type":"string","description":"Start date","format":"date","minLength":10}},"required":["when"]}"#)
        let description = try #require(emitted["properties"]?["when"]?["description"]?.stringValue)
        #expect(description.hasPrefix("Start date"))
        #expect(description.contains(#"format: "date""#))
        #expect(description.contains("minLength: 10"))
    }

    @Test(arguments: [
        (#"{"type":"object","properties":{"a":{"allOf":[{"type":"string"}]}}}"#, "$.properties.a.allOf"),
        (#"{"type":"object","properties":{"a":{"not":{"type":"string"}}}}"#, "$.properties.a.not"),
        (#"{"type":"object","properties":{"a":{"type":"object","additionalProperties":{"type":"string"}}}}"#, "$.properties.a.additionalProperties"),
        (#"{"type":"object","properties":{"a":{"enum":[1,2,3]}}}"#, "$.properties.a.enum"),
        (#"{"type":"object","properties":{"a":{"type":"array"}}}"#, "$.properties.a"),
        (#"{"type":"object","properties":{"a":{"description":"anything"}}}"#, "$.properties.a"),
        (#"{"type":"object","properties":{"a":{"$ref":"https://example.com/schema.json"}}}"#, "$.properties.a.$ref"),
        (#"{"type":"object","properties":{"a":{"type":"string","pattern":"("}}}"#, "$.properties.a.pattern"),
        (#"{"type":"array","items":{"type":"string"}}"#, "$.type"),
    ])
    func rejectsWhatCannotBeRepresented(schema: String, path: String) throws {
        #expect(try rejection(schema).path == path)
    }
}
