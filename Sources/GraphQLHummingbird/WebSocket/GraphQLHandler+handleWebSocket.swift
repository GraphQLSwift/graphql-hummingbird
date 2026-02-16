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
        let messenger = WebSocketMessenger(outbound: outbound, logger: logger)

        let messageStream = inbound.messages(maxSize: context.requestContext.maxUploadSize).compactMap { message -> String? in
            // TODO: Add binary support
            guard case let .text(text) = message else {
                return nil
            }
            logger.trace("GraphQL server received: \(message)")
            return text
        }

        switch subProtocol {
        case .graphqlTransportWs:
            // https://github.com/enisdenjo/graphql-ws/blob/master/PROTOCOL.md
            let server = GraphQLTransportWS.Server<WebSocketInit, WebSocketInitResult, AsyncThrowingStream<GraphQLResult, Error>>(
                messenger: messenger,
                onInit: { initPayload in
                    try await config.websocket.onWebSocketInit(initPayload, context.request, context.requestContext)
                },
                onExecute: { graphQLRequest, initResult in
                    let graphQLContextComputationInputs = GraphQLContextComputationInputs<Context, WebSocketInitResult>(
                        hummingbirdRequest: context.request,
                        hummingbirdContext: context.requestContext,
                        graphQLRequest: graphQLRequest,
                        websocketInitResult: initResult
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
                onSubscribe: { graphQLRequest, initResult in
                    let graphQLContextComputationInputs = GraphQLContextComputationInputs<Context, WebSocketInitResult>(
                        hummingbirdRequest: context.request,
                        hummingbirdContext: context.requestContext,
                        graphQLRequest: graphQLRequest,
                        websocketInitResult: initResult
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
            try await server.listen(to: messageStream)
        case .graphqlWs:
            // https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md
            let server = GraphQLWS.Server<WebSocketInit, WebSocketInitResult, AsyncThrowingStream<GraphQLResult, Error>>(
                messenger: messenger,
                onInit: { initPayload in
                    try await config.websocket.onWebSocketInit(initPayload, context.request, context.requestContext)
                },
                onExecute: { graphQLRequest, initResult in
                    let graphQLContextComputationInputs = GraphQLContextComputationInputs<Context, WebSocketInitResult>(
                        hummingbirdRequest: context.request,
                        hummingbirdContext: context.requestContext,
                        graphQLRequest: graphQLRequest,
                        websocketInitResult: initResult
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
                onSubscribe: { graphQLRequest, initResult in
                    let graphQLContextComputationInputs = GraphQLContextComputationInputs<Context, WebSocketInitResult>(
                        hummingbirdRequest: context.request,
                        hummingbirdContext: context.requestContext,
                        graphQLRequest: graphQLRequest,
                        websocketInitResult: initResult
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
            try await server.listen(to: messageStream)
        }
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
