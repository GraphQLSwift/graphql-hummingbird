import GraphQL
import Hummingbird
import HummingbirdWebSocket

public extension Router {
    /// Registers graphql routes that respond using the provided schema.
    ///
    /// The resulting routes adhere to the [GraphQL over HTTP spec](https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md).
    /// The configured IDE is available by making a `GET` request to the path with no query parameter.
    ///
    /// WebSockets are not supported by the resulting route at this time.
    ///
    /// - Parameters:
    ///   - path: The route that should respond to GraphQL requests. Both `GET` and `POST` routes are registered.
    ///   - schema: The GraphQL schema that should be used to respond to requests.
    ///   - rootValue: The `rootValue` GraphQL execution arg. This is the object passed to the root resolvers.
    ///   - config: GraphQL Handler configuration options. See type documentation for details.
    ///   - computeContext: A closure used to compute the GraphQL context from incoming requests. This must be provided.
    @discardableResult
    func graphql<GraphQLContext: Sendable>(
        _ path: RouterPath = "graphql",
        schema: GraphQLSchema,
        rootValue: any Sendable = (),
        config: GraphQLConfig<EmptyWebSocketInit> = .init(),
        computeContext: @Sendable @escaping (Request, Context) async throws -> GraphQLContext
    ) -> Self {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#request
        let handler = GraphQLHandler<Context, GraphQLContext, EmptyWebSocketInit>(
            schema: schema,
            rootValue: rootValue,
            config: config,
            computeContext: computeContext
        )

        get(path) { request, context -> Response in
            // Get requests without a `query` parameter are considered to be IDE requests
            let hasQueryParam = request.uri.query?.contains("query") ?? false
            if !hasQueryParam {
                switch config.ide.type {
                case .graphiql:
                    let url = request.uri.path
                    // Assume that we have a subscription websocket at the same route.
                    let subscriptionUrl = url.replacingOccurrences(of: "http://", with: "ws://").replacingOccurrences(of: "https://", with: "wss://")
                    return try await GraphiQLHandler.respond(
                        url: url,
                        subscriptionUrl: subscriptionUrl
                    )
                case .none:
                    // Let this get caught by the graphQLRequest decoding
                    break
                }
            }

            // Normal GET request handling
            guard config.allowGet else {
                throw HTTPError(.methodNotAllowed, message: "GET requests are disallowed")
            }
            return try await handler.handleGet(request: request, context: context)
        }

        post(path) { request, context in
            try await handler.handlePost(request: request, context: context)
        }

        return self
    }
}

public extension Router where Context: WebSocketRequestContext {
    /// Registers a graphql websocket route that responds using the provided schema.
    ///
    /// WebSocket requests support the
    /// [`graphql-transport-ws`](https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md)
    /// and [`graphql-ws`](https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md)
    /// subprotocols.
    ///
    /// - Parameters:
    ///   - path: The route that should respond to GraphQL requests. Both `GET` and `POST` routes are registered.
    ///   - schema: The GraphQL schema that should be used to respond to requests.
    ///   - rootValue: The `rootValue` GraphQL execution arg. This is the object passed to the root resolvers.
    ///   - config: GraphQL Handler configuration options. See type documentation for details. Note that all non-WebSocket values are ignored.
    ///   - computeContext: A closure used to compute the GraphQL context from incoming requests. This must be provided.
    @discardableResult
    func graphqlWebSocket<
        GraphQLContext: Sendable,
        WebSocketInit: Equatable & Codable & Sendable
    >(
        _ path: RouterPath = "graphql",
        schema: GraphQLSchema,
        rootValue: any Sendable = (),
        config: GraphQLConfig<WebSocketInit> = GraphQLConfig<EmptyWebSocketInit>(),
        computeContext: @Sendable @escaping (Request, Context) async throws -> GraphQLContext
    ) -> Self {
        let handler = GraphQLHandler<Context, GraphQLContext, WebSocketInit>(
            schema: schema,
            rootValue: rootValue,
            config: config,
            computeContext: computeContext
        )

        ws(path, shouldUpgrade: { request, _ in
            try handler.shouldUpgrade(request: request)
        }) { inbound, outbound, context in
            let graphQLContext = try await computeContext(context.request, context.requestContext)
            let subProtocol = try handler.negotiateSubProtocol(request: context.request)
            try await handler.handleWebSocket(
                inbound: inbound,
                outbound: outbound,
                graphqlContext: graphQLContext,
                subProtocol: subProtocol,
                logger: context.logger
            )
        }
        return self
    }
}
