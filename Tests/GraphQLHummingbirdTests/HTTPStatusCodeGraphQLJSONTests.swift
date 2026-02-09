import Foundation
import GraphQL
@testable import GraphQLHummingbird
import GraphQLTransportWS
import GraphQLWS
import Hummingbird
import HummingbirdTesting
import NIOFoundationCompat
import Testing

/// Validates status code behavior for the `application/graphql-response+json` media type.
///
/// https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#applicationgraphql-responsejson
@Suite
struct HTTPStatusCodeGraphQLJSONTests {
    @Test func parsingFailureGivesBadRequest() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#json-parsing-failure-1
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonGraphQLHeaders,
                body: .init(data: #require(#"{"query":"#.data(using: .utf8)))
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test func invalidParametersGivesBadRequest() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#invalid-parameters-1
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonGraphQLHeaders,
                body: .init(data: #require(#"{"qeury": "{__typename}"}"#.data(using: .utf8)))
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test func documentParsingFailureGivesBadRequest() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#document-parsing-failure-1
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonGraphQLHeaders,
                body: .init(data: #require(#"{"query": "{"}"#.data(using: .utf8)))
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test func documentValidationFailureGivesBadRequest() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#document-validation-failure-1
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonGraphQLHeaders,
                // Fails "No Unused Variables" validation rule
                body: .init(data: #require(#"{"query": "query A($name: String) { hello }"}"#.data(using: .utf8)))
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test func operationCannotBeDeterminedGivesBadRequest() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#operation-cannot-be-determined-1
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonGraphQLHeaders,
                body: .init(data: #require(#"{"query": "abc { hello }"}"#.data(using: .utf8)))
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test func variableCoercionFailureGivesBadRequest() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#variable-coercion-failure-1
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
                headers: jsonGraphQLHeaders,
                body: .init(data: #require(
                    #"{"query": "query getName($name: String!) { get(name: $name) }", "variables": { "name": null }}"#.data(using: .utf8)
                ))
            ) { response in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test func fieldErrorGivesOk() async throws {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#field-errors-encountered-during-execution-1
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
