import Foundation
import GraphQL
@testable import GraphQLHummingbird
import GraphQLTransportWS
import GraphQLWS
import Hummingbird
import HummingbirdTesting
import NIOFoundationCompat
import Testing

@Suite
struct HTTPTests {
    @Test func query() async throws {
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
                body: .init(data: defaultJSONEncoder.encode(GraphQLRequest(query: "{ hello }")))
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/graphql-response+json; charset=utf-8")

                let result = try defaultJSONDecoder.decode(GraphQLResult.self, from: response.body)
                #expect(result.data?["hello"] == "World")
                #expect(result.errors.isEmpty)
            }
        }
    }

    @Test func queryWithVariables() async throws {
        let schema = try GraphQLSchema(
            query: GraphQLObjectType(
                name: "Query",
                fields: [
                    "greet": GraphQLField(
                        type: GraphQLString,
                        args: [
                            "name": GraphQLArgument(type: GraphQLString),
                        ],
                        resolve: { _, args, _, _ in
                            guard let name = args["name"].string else {
                                return "Hello, stranger"
                            }
                            return "Hello, \(name)"
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
                body: .init(data: defaultJSONEncoder.encode(GraphQLRequest(
                    query: "query Greet($name: String) { greet(name: $name) }",
                    variables: ["name": "Alice"]
                )))
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/graphql-response+json; charset=utf-8")

                let result = try defaultJSONDecoder.decode(GraphQLResult.self, from: response.body)
                #expect(result.data?["greet"] == "Hello, Alice")
                #expect(result.errors.isEmpty)
            }
        }
    }

    @Test func queryWithContext() async throws {
        struct Context: Sendable {
            let message: String
        }

        let schema = try GraphQLSchema(
            query: GraphQLObjectType(
                name: "Query",
                fields: [
                    "contextMessage": GraphQLField(
                        type: GraphQLString,
                        resolve: { _, _, context, _ in
                            guard let ctx = context as? Context else {
                                throw GraphQLError(message: "Invalid context")
                            }
                            return ctx.message
                        }
                    ),
                ]
            )
        )

        let router = Router()
        router.graphql(schema: schema) { _ in
            Context(message: "Hello from context!")
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonGraphQLHeaders,
                body: .init(data: defaultJSONEncoder.encode(GraphQLRequest(query: "{ contextMessage }")))
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/graphql-response+json; charset=utf-8")

                let result = try defaultJSONDecoder.decode(GraphQLResult.self, from: response.body)
                #expect(result.data?["contextMessage"] == "Hello from context!")
                #expect(result.errors.isEmpty)
            }
        }
    }

    @Test func jsonAcceptHeader() async throws {
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: [
                    .accept: MediaType.applicationJson.description,
                    .contentType: MediaType.applicationJsonGraphQL.description,
                ],
                body: .init(data: defaultJSONEncoder.encode(GraphQLRequest(query: "{ hello }")))
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/json; charset=utf-8")

                let result = try defaultJSONDecoder.decode(GraphQLResult.self, from: response.body)
                #expect(result.data?["hello"] == "World")
                #expect(result.errors.isEmpty)
            }
        }
    }

    @Test func jsonContentTypeHeader() async throws {
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: [
                    .accept: MediaType.applicationJsonGraphQL.description,
                    .contentType: MediaType.applicationJson.description,
                ],
                body: .init(data: defaultJSONEncoder.encode(GraphQLRequest(query: "{ hello }")))
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/graphql-response+json; charset=utf-8")

                let result = try defaultJSONDecoder.decode(GraphQLResult.self, from: response.body)
                #expect(result.data?["hello"] == "World")
                #expect(result.errors.isEmpty)
            }
        }
    }

    @Test func noAcceptHeader() async throws {
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: [
                    .contentType: MediaType.applicationJsonGraphQL.description,
                ],
                body: .init(data: defaultJSONEncoder.encode(GraphQLRequest(query: "{ hello }")))
            ) { response in
                #expect(response.status == .notAcceptable)
            }
        }
    }

    @Test func defaultAcceptHeader() async throws {
        let router = Router()
        router.graphql(schema: helloWorldSchema, config: .init(allowMissingAcceptHeader: true)) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: [
                    .contentType: MediaType.applicationJsonGraphQL.description,
                ],
                body: .init(data: defaultJSONEncoder.encode(GraphQLRequest(query: "{ hello }")))
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/graphql-response+json; charset=utf-8")

                let result = try defaultJSONDecoder.decode(GraphQLResult.self, from: response.body)
                #expect(result.data?["hello"] == "World")
                #expect(result.errors.isEmpty)
            }
        }
    }

    @Test func allowGetRequest() async throws {
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql?query=%7Bhello%7D",
                method: .get,
                headers: jsonGraphQLHeaders
            ) { response in
                #expect(response.status == .ok)

                let result = try defaultJSONDecoder.decode(GraphQLResult.self, from: response.body)
                #expect(result.data?["hello"] == "World")
                #expect(result.errors.isEmpty)
            }
        }
    }

    @Test func disallowGetRequest() async throws {
        let router = Router()
        router.graphql(
            schema: helloWorldSchema,
            config: .init(
                allowGet: false
            )
        ) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql?query=%7Bhello%7D",
                method: .get,
                headers: jsonGraphQLHeaders
            ) { response in
                #expect(response.status == .methodNotAllowed)
            }
        }
    }

    @Test func graphiql() async throws {
        let router = Router()
        router.graphql(schema: helloWorldSchema) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                var responseBuffer = response.body
                let result = responseBuffer.readString(length: responseBuffer.readableBytes)
                #expect(result == GraphiQLHandler.html(url: "/graphql", subscriptionUrl: "/graphql"))
            }
        }
    }

    @Test func graphiqlSubscription() async throws {
        let router = Router()
        router.graphql(schema: helloWorldSchema, config: .init(subscriptionProtocols: [.websocket])) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .get
            ) { response in
                #expect(response.status == .ok)
                var responseBuffer = response.body
                let result = responseBuffer.readString(length: responseBuffer.readableBytes)
                #expect(result == GraphiQLHandler.html(url: "/graphql", subscriptionUrl: "/graphql"))
            }
        }
    }

    @Test func customEncoder() async throws {
        let graphQLJSONEncoder = GraphQLJSONEncoder()
        graphQLJSONEncoder.dateEncodingStrategy = .secondsSince1970
        let router = Router()
        router.graphql(
            schema: helloWorldSchema,
            config: .init(
                coders: .init(graphQLJSONEncoder: graphQLJSONEncoder)
            )
        ) { _ in
            EmptyContext()
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/graphql",
                method: .post,
                headers: jsonGraphQLHeaders,
                body: .init(data: defaultJSONEncoder.encode(GraphQLRequest(query: "{ hello }")))
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "application/graphql-response+json; charset=utf-8")

                let result = try defaultJSONDecoder.decode(GraphQLResult.self, from: response.body)
                #expect(result.data?["hello"] == "World")
                #expect(result.errors.isEmpty)
            }
        }
    }
}
