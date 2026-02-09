import GraphQL
import Hummingbird

struct GraphQLHandler<
    Context: RequestContext,
    GraphQLContext: Sendable,
    WebSocketInit: Equatable & Codable & Sendable
>: Sendable {
    let schema: GraphQLSchema
    let rootValue: any Sendable
    let config: GraphQLConfig<WebSocketInit>
    let computeContext: @Sendable (GraphQLContextComputationInputs<Context>) async throws -> GraphQLContext
}

public struct GraphQLContextComputationInputs<
    Context: RequestContext
>: Sendable {
    public let hummingbirdRequest: Request
    public let hummingbirdContext: Context
    public let graphQLRequest: GraphQLRequest
}
