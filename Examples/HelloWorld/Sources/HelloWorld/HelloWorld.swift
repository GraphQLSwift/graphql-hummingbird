import AsyncAlgorithms
import GraphQL
import GraphQLHummingbird
import Hummingbird
import HummingbirdWebSocket
import Logging

@main
struct HelloWorld {
    static func main() async throws {
        let schema = try GraphQLSchema(
            query: GraphQLObjectType(
                name: "Query",
                fields: [
                    "hello": GraphQLField(
                        type: GraphQLString,
                        resolve: { _, _, _, _ in
                            "World"
                        }
                    ),
                ]
            ),
            subscription: GraphQLObjectType(
                name: "Subscription",
                fields: [
                    "hello": GraphQLField(
                        type: GraphQLString,
                        description: "Emits an updated `World` message every 3 seconds",
                        resolve: { eventResult, _, _, _ in
                            eventResult
                        },
                        subscribe: { _, _, _, _ in
                            let clock = ContinuousClock()
                            let start = clock.now
                            return AsyncTimerSequence(interval: .seconds(3), clock: ContinuousClock()).map { instant in
                                "World at \(start.duration(to: instant))"
                            }
                        }
                    ),
                ]
            )
        )

        let router = Router(context: HummingbirdContext.self)
        router.graphql(schema: schema, config: .init(allowMissingAcceptHeader: true)) { _ in
            GraphQLContext()
        }
        let webSocketRouter = Router(context: HummingbirdWebSocketContext.self)
        webSocketRouter.graphqlWebSocket(schema: schema) { _ in
            GraphQLContext()
        }
        let app = Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: webSocketRouter)
        )
        try await app.runService()
    }

    struct GraphQLContext: @unchecked Sendable {}

    struct HummingbirdContext: RequestContext {
        var coreContext: Hummingbird.CoreRequestContextStorage
        var logger: Logging.Logger

        init(source: Hummingbird.ApplicationRequestContextSource) {
            coreContext = .init(source: source)
            logger = source.logger
        }
    }

    struct HummingbirdWebSocketContext: WebSocketRequestContext, RequestContext {
        var coreContext: Hummingbird.CoreRequestContextStorage
        var webSocket: HummingbirdWebSocket.WebSocketHandlerReference<Self>
        var logger: Logging.Logger

        init(source: Hummingbird.ApplicationRequestContextSource) {
            coreContext = .init(source: source)
            webSocket = .init()
            logger = source.logger
        }
    }
}
