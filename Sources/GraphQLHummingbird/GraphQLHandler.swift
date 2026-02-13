import GraphQL
import Hummingbird

struct GraphQLHandler<
    Context: RequestContext,
    GraphQLContext: Sendable,
    WebSocketInit: Equatable & Codable & Sendable,
    WebSocketInitResult: Sendable
>: Sendable {
    let schema: GraphQLSchema
    let rootValue: any Sendable
    let config: GraphQLConfig<Context, WebSocketInit, WebSocketInitResult>
    let computeContext: @Sendable (GraphQLContextComputationInputs<Context, WebSocketInitResult>) async throws -> GraphQLContext
}

/// Request metadata that can be used to construct a GraphQL context
public struct GraphQLContextComputationInputs<
    Context: RequestContext,
    WebSocketInitResult: Sendable
>: Sendable {
    /// The Hummingbird request that initiated the GraphQL request. In WebSockets, this is the upgrade GET request.
    public let hummingbirdRequest: Request

    /// The Hummingbird context from the request that initiated the GraphQL request. In WebSockets, this is the context from the upgrade GET request.
    public let hummingbirdContext: Context

    /// The decoded GraphQL request, including the raw query, variables, and more
    public let graphQLRequest: GraphQLRequest

    /// The result of the WebSocket's initialization closure. This can be used to customize GraphQL context creation based on the init
    /// message metadata as opposed to only the upgrade request. In non-WebSocket contexts, this is nil.
    public let websocketInitResult: WebSocketInitResult?
}
