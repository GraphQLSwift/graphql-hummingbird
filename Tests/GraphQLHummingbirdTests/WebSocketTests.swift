import Foundation
import GraphQL
@testable import GraphQLHummingbird
import GraphQLTransportWS
import GraphQLWS
import Hummingbird
import HummingbirdWebSocket
import HummingbirdWSTesting
import Logging
import Testing

@Suite
struct WebSocketTests {
    let decoder = JSONDecoder()
    let encoder = GraphQLJSONEncoder()

    @Test func subscription() async throws {
        let pubsub = SimplePubSub<String>()
        let schema = try GraphQLSchema(
            subscription: GraphQLObjectType(
                name: "Subscription",
                fields: [
                    "hello": GraphQLField(
                        type: GraphQLString,
                        resolve: { source, _, _, _ in
                            source as! String
                        },
                        subscribe: { _, _, _, _ in
                            await pubsub.subscribe()
                        }
                    ),
                ]
            )
        )

        let router = Router(context: TestWebSocketContext.self)
        router.graphqlWebSocket(schema: schema) { _, _ in
            EmptyContext()
        }
        let app = Application(
            router: Router(),
            server: .http1WebSocketUpgrade(webSocketRouter: router),
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )

        _ = try await app.test(.live) { client in
            try await client.ws(
                "/graphql",
                configuration: .init(additionalHeaders: [.secWebSocketProtocol: "graphql-transport-ws"])
            ) { inbound, outbound, _ in
                // Start the sequence
                try await outbound.write(.text(#"{"type": "connection_init", "payload": {}}"#))
                for try await message in inbound.messages(maxSize: 1024 * 1024) {
                    guard case let .text(message) = message else { return }
                    #expect(!message.starts(with: "44"))
                    let response = try #require(message.data(using: .utf8))
                    if let _ = try? decoder.decode(GraphQLTransportWS.ConnectionAckResponse.self, from: response) {
                        try await outbound.write(.text(#"""
                        {
                            "type": "subscribe",
                            "payload": {
                                "query": "subscription { hello }"
                            },
                            "id": "1"
                        }
                        """#))
                        // Must wait for a few milliseconds for the subscription to get set up.
                        try await Task.sleep(for: .milliseconds(10))
                        // Force the server to emit an event
                        await pubsub.emit(event: "World")
                    } else if let next = try? decoder.decode(GraphQLTransportWS.NextResponse.self, from: response) {
                        #expect(next.payload?.errors == [])
                        #expect(next.payload?.data == ["hello": "World"])
                        try await outbound.write(.text(#"{"type": "complete", "id": "1"}"#))
                        await pubsub.cancel()
                        break
                    } else if let _ = try? decoder.decode(GraphQLTransportWS.CompleteResponse.self, from: response) {
                        try await outbound.close(.goingAway, reason: nil)
                        break
                    } else if let _ = try? decoder.decode(GraphQLTransportWS.ErrorResponse.self, from: response) {
                        Issue.record("Error message: \(message)")
                        break
                    } else {
                        Issue.record("Unrecognized message: \(message)")
                        break
                    }
                }
            }
        }
    }

    @Test func subscription_GraphQLWS() async throws {
        let pubsub = SimplePubSub<String>()
        let schema = try GraphQLSchema(
            subscription: GraphQLObjectType(
                name: "Subscription",
                fields: [
                    "hello": GraphQLField(
                        type: GraphQLString,
                        resolve: { source, _, _, _ in
                            source as! String
                        },
                        subscribe: { _, _, _, _ in
                            await pubsub.subscribe()
                        }
                    ),
                ]
            )
        )

        let router = Router(context: TestWebSocketContext.self)
        router.graphqlWebSocket(schema: schema) { _, _ in
            EmptyContext()
        }
        let app = Application(
            router: Router(),
            server: .http1WebSocketUpgrade(webSocketRouter: router),
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )

        _ = try await app.test(.live) { client in
            try await client.ws(
                "/graphql",
                configuration: .init(additionalHeaders: [.secWebSocketProtocol: "graphql-ws"])
            ) { inbound, outbound, _ in
                // Start the sequence
                try await outbound.write(.text(#"{"type": "connection_init", "payload": {}}"#))
                for try await message in inbound.messages(maxSize: 1024 * 1024) {
                    guard case let .text(message) = message else { return }
                    #expect(!message.starts(with: "44"))
                    let response = try #require(message.data(using: .utf8))
                    if let _ = try? decoder.decode(GraphQLWS.ConnectionAckResponse.self, from: response) {
                        try await outbound.write(.text(#"""
                        {
                            "type": "start",
                            "payload": {
                                "query": "subscription { hello }"
                            },
                            "id": "1"
                        }
                        """#))
                        // Must wait for a few milliseconds for the subscription to get set up.
                        try await Task.sleep(for: .milliseconds(10))
                        // Force the server to emit an event
                        await pubsub.emit(event: "World")
                    } else if let next = try? decoder.decode(GraphQLWS.DataResponse.self, from: response) {
                        #expect(next.payload?.errors == [])
                        #expect(next.payload?.data == ["hello": "World"])
                        try await outbound.write(.text(#"{"type": "complete", "id": "1"}"#))
                        await pubsub.cancel()
                        break
                    } else if let _ = try? decoder.decode(GraphQLWS.CompleteResponse.self, from: response) {
                        try await outbound.close(.goingAway, reason: nil)
                        break
                    } else if let _ = try? decoder.decode(GraphQLWS.ErrorResponse.self, from: response) {
                        Issue.record("Error message: \(message)")
                        break
                    } else {
                        Issue.record("Unrecognized message: \(message)")
                        break
                    }
                }
            }
        }
    }

    @Test func badSubProtocolFailsToUpgrade() async throws {
        let pubsub = SimplePubSub<String>()
        let schema = try GraphQLSchema(
            subscription: GraphQLObjectType(
                name: "Subscription",
                fields: [
                    "hello": GraphQLField(
                        type: GraphQLString,
                        resolve: { source, _, _, _ in
                            source as! String
                        },
                        subscribe: { _, _, _, _ in
                            await pubsub.subscribe()
                        }
                    ),
                ]
            )
        )

        let router = Router(context: TestWebSocketContext.self)
        router.graphqlWebSocket(schema: schema) { _, _ in
            EmptyContext()
        }
        let app = Application(
            router: Router(),
            server: .http1WebSocketUpgrade(webSocketRouter: router),
            configuration: .init(address: .hostname("127.0.0.1", port: 0))
        )

        _ = try await app.test(.live) { client in
            await #expect(throws: Error.self) {
                try await client.ws(
                    "/graphql",
                    configuration: .init(additionalHeaders: [.secWebSocketProtocol: "bad"])
                ) { _, _, _ in
                    // Should never enter
                }
            }
        }
    }
}

struct TestWebSocketContext: WebSocketRequestContext, RequestContext {
    typealias GraphQLContext = EmptyContext
    var coreContext: Hummingbird.CoreRequestContextStorage
    var webSocket: HummingbirdWebSocket.WebSocketHandlerReference<TestWebSocketContext>
    var logger: Logging.Logger

    init(source: Hummingbird.ApplicationRequestContextSource) {
        coreContext = .init(source: source)
        webSocket = .init()
        logger = source.logger
    }
}

/// A very simple publish/subscriber used for testing
actor SimplePubSub<T: Sendable>: Sendable {
    private var subscribers: [Subscriber<T>]

    init() {
        subscribers = []
    }

    func emit(event: T) {
        for subscriber in subscribers {
            subscriber.callback(event)
        }
    }

    func cancel() {
        for subscriber in subscribers {
            subscriber.cancel()
        }
    }

    func subscribe() -> AsyncThrowingStream<T, Error> {
        return AsyncThrowingStream<T, Error> { continuation in
            let subscriber = Subscriber<T>(
                callback: { newValue in
                    continuation.yield(newValue)
                },
                cancel: {
                    continuation.finish()
                }
            )
            subscribers.append(subscriber)
        }
    }
}

struct Subscriber<T> {
    let callback: (T) -> Void
    let cancel: () -> Void
}
