import Foundation
import GraphQL
@testable import GraphQLHummingbird
import GraphQLTransportWS
import GraphQLWS
import Hummingbird
import HummingbirdTesting
import NIOFoundationCompat
import Testing

/// Validates status code behavior for the `application/json` media type.
///
/// https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#applicationjson
@Suite
struct HTTPStatusCodeJSONTests {
    @Test func parsingFailureGivesBadRequest() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#json-parsing-failure
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonHeaders,
                body: .init(data: #require(#"{"query":"#.data(using: .utf8)))
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test func invalidParametersGivesBadRequest() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#invalid-parameters
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonHeaders,
                body: .init(data: #require(#"{"qeury": "{__typename}"}"#.data(using: .utf8)))
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test func documentValidationFailureGivesOk() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#document-validation-failure
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonHeaders,
                // Fails "No Unused Variables" validation rule
                body: .init(data: #require(#"{"query": "query A($name: String) { hello }"}"#.data(using: .utf8)))
            ) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test func documentParsingFailureGivesOk() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#document-parsing-failure
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonHeaders,
                body: .init(data: #require(#"{"query": "{"}"#.data(using: .utf8)))
            ) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test func variableCoercionFailureGivesOk() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#variable-coercion-failure
        let schema = try GraphQLSchema(
            query: GraphQLObjectType(
                name: "Query",
                fields: [
                    "get": GraphQLField(
                        type: GraphQLString,
                        args: [
                            "name": GraphQLArgument(type: GraphQLString),
                        ],
                        resolve: { _, args, _, _ in
                            guard let name = args["name"].string else {
                                throw GraphQLError(message: "Name arg is required")
                            }
                            return name
                        }
                    ),
                ]
            )
        )
        let router = Router()
        router.graphql(schema: schema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonHeaders,
                body: .init(data: #require(
                    #"{"query": "query getName($name: String!) { get(name: $name) }", "variables": { "name": null }}"#.data(using: .utf8)
                ))
            ) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test func operationCannotBeDeterminedGivesOk() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#operation-cannot-be-determined
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonHeaders,
                body: .init(data: #require(#"{"query": "abc { hello }"}"#.data(using: .utf8)))
            ) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test func fieldErrorGivesOk() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#field-errors-encountered-during-execution
        let schema = try GraphQLSchema(
            query: GraphQLObjectType(
                name: "Query",
                fields: [
                    "error": GraphQLField(
                        type: GraphQLString,
                        resolve: { _, _, _, _ in
                            throw GraphQLError(message: "Something went wrong")
                        }
                    ),
                ]
            )
        )
        let router = Router()
        router.graphql(schema: schema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonGraphQLHeaders,
                body: .init(data: defaultJSONEncoder.encode(GraphQLRequest(query: "{ error }")))
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/graphql-response+json; charset=utf-8")

                let result = try defaultJSONDecoder.decode(GraphQLResult.self, from: response.body)
                #expect(!result.errors.isEmpty)
                #expect(result.errors.first?.message == "Something went wrong")
            }
        }
    }
}
