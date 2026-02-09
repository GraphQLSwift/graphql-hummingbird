import GraphQL
import struct GraphQLTransportWS.EmptyInitPayload
import class GraphQLTransportWS.Server
import class GraphQLWS.Server
import Hummingbird
import HummingbirdWebSocket
import Logging

extension GraphQLHandler where Context: WebSocketRequestContext {
    func handleWebSocket(
        inbound: WebSocketInboundStream,
        outbound: WebSocketOutboundWriter,
        context: WebSocketRouterContext<Context>,
        subProtocol: WebSocketSubProtocol,
        logger: Logger
    ) async throws {
        let messenger = WebSocketMessenger(inbound: inbound, outbound: outbound, logger: logger)

        switch subProtocol {
        case .graphqlTransportWs:
            // https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md
            let server = GraphQLTransportWS.Server<WebSocketInit, AsyncThrowingStream<GraphQLResult, Error>>(
                messenger: messenger,
                onExecute: { graphQLRequest in
                    let graphQLContextComputationInputs = GraphQLContextComputationInputs<Context>(
                        hummingbirdRequest: context.request,
                        hummingbirdContext: context.requestContext,
                        graphQLRequest: graphQLRequest
                    )
                    let graphQLContext = try await computeContext(graphQLContextComputationInputs)
                    return try await graphql(
                        schema: self.schema,
                        request: graphQLRequest.query,
                        rootValue: self.rootValue,
                        context: graphQLContext,
                        variableValues: graphQLRequest.variables,
                        operationName: graphQLRequest.operationName
                    )
                },
                onSubscribe: { graphQLRequest in
                    let graphQLContextComputationInputs = GraphQLContextComputationInputs<Context>(
                        hummingbirdRequest: context.request,
                        hummingbirdContext: context.requestContext,
                        graphQLRequest: graphQLRequest
                    )
                    let graphQLContext = try await computeContext(graphQLContextComputationInputs)
                    return try await graphqlSubscribe(
                        schema: self.schema,
                        request: graphQLRequest.query,
                        rootValue: self.rootValue,
                        context: graphQLContext,
                        variableValues: graphQLRequest.variables,
                        operationName: graphQLRequest.operationName
                    ).get()
                }
            )
            server.onMessage { message in
                logger.trace("GraphQL server received: \(String(message))")
            }
            server.auth(config.websocket.onWebSocketInit)
        case .graphqlWs:
            // https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md
            let server = GraphQLWS.Server<WebSocketInit, AsyncThrowingStream<GraphQLResult, Error>>(
                messenger: messenger,
                onExecute: { graphQLRequest in
                    let graphQLContextComputationInputs = GraphQLContextComputationInputs<Context>(
                        hummingbirdRequest: context.request,
                        hummingbirdContext: context.requestContext,
                        graphQLRequest: graphQLRequest
                    )
                    let graphQLContext = try await computeContext(graphQLContextComputationInputs)
                    return try await graphql(
                        schema: self.schema,
                        request: graphQLRequest.query,
                        rootValue: self.rootValue,
                        context: graphQLContext,
                        variableValues: graphQLRequest.variables,
                        operationName: graphQLRequest.operationName
                    )
                },
                onSubscribe: { graphQLRequest in
                    let graphQLContextComputationInputs = GraphQLContextComputationInputs<Context>(
                        hummingbirdRequest: context.request,
                        hummingbirdContext: context.requestContext,
                        graphQLRequest: graphQLRequest
                    )
                    let graphQLContext = try await computeContext(graphQLContextComputationInputs)
                    return try await graphqlSubscribe(
                        schema: self.schema,
                        request: graphQLRequest.query,
                        rootValue: self.rootValue,
                        context: graphQLContext,
                        variableValues: graphQLRequest.variables,
                        operationName: graphQLRequest.operationName
                    ).get()
                }
            )
            server.onMessage { message in
                logger.trace("GraphQL server received: \(String(message))")
            }
            server.auth(config.websocket.onWebSocketInit)
        }
        try await messenger.start()
    }

    func shouldUpgrade(request: Request) throws -> RouterShouldUpgrade {
        let subProtocol = try negotiateSubProtocol(request: request)
        return .upgrade([.secWebSocketProtocol: subProtocol.rawValue])
    }

    func negotiateSubProtocol(request: Request) throws -> WebSocketSubProtocol {
        var subProtocol: WebSocketSubProtocol?
        let requestedSubProtocols = request.headers[values: .secWebSocketProtocol]
        if requestedSubProtocols.isEmpty {
            // Default
            subProtocol = .graphqlTransportWs
        } else {
            // Choose highest client preference that we understand
            for requestedSubProtocol in requestedSubProtocols {
                if let selectedSubProtocol = WebSocketSubProtocol(rawValue: requestedSubProtocol) {
                    subProtocol = selectedSubProtocol
                    break
                }
            }
        }
        guard let subProtocol = subProtocol else {
            // If they provided options but none matched, fail
            throw HTTPError(.badRequest, message: "Unable to negotiate subprotocol. \(WebSocketSubProtocol.allCases) are supported.")
        }
        return subProtocol
    }
}
