import Foundation
import GraphQL
import Hummingbird

/// Configuration options for GraphQLHummingbird
public struct GraphQLConfig<WebSocketInit: Equatable & Codable & Sendable>: Sendable {
    let allowGet: Bool
    let allowMissingAcceptHeader: Bool
    let coders: Coders
    let ide: IDE
    let subscriptionProtocols: Set<SubscriptionProtocol>
    let websocket: WebSocket
    let additionalValidationRules: [@Sendable (ValidationContext) -> Visitor]

    /// Configuration options for GraphQLHummingbird
    /// - Parameters:
    ///   - allowGet: Whether to allow GraphQL queries via `GET` requests.
    ///   - allowMissingAcceptHeader: Whether to allow clients to omit "Accept" headers and default to `application/graphql-response+json` encoded responses.
    ///   - ide: The IDE to expose
    ///   - subscriptionProtocols: Protocols used to support GraphQL subscription requests
    ///   - websocket: WebSocket-specific configuration
    ///   - additionalValidationRules: Additional validation rules to apply to requests. The default GraphQL validation rules are always applied.
    public init(
        allowGet: Bool = true,
        allowMissingAcceptHeader: Bool = false,
        coders: Coders = .init(),
        ide: IDE = .graphiql,
        subscriptionProtocols: Set<SubscriptionProtocol> = [.websocket],
        websocket: WebSocket = .init(
            // Including this strongly-typed argument is required to avoid compiler failures on Swift 6.2.3.
            onWebSocketInit: { (_: EmptyWebSocketInit) in }
        ),
        additionalValidationRules: [@Sendable (ValidationContext) -> Visitor] = []
    ) {
        self.allowGet = allowGet
        self.allowMissingAcceptHeader = allowMissingAcceptHeader
        self.additionalValidationRules = additionalValidationRules
        self.coders = coders
        self.ide = ide
        self.subscriptionProtocols = subscriptionProtocols
        self.websocket = websocket
    }

    public struct Coders: Sendable {
        public let graphQLJSONEncoder: GraphQLJSONEncoder
        public let jsonDecoder: JSONDecoder
        public let jsonEncoder: JSONEncoder
        public let urlEncodedFormDecoder: URLEncodedFormDecoder
        public let urlEncodedFormEncoder: URLEncodedFormEncoder

        public init(
            graphQLJSONEncoder: GraphQLJSONEncoder? = nil,
            jsonDecoder: JSONDecoder? = nil,
            jsonEncoder: JSONEncoder? = nil,
            urlEncodedFormDecoder: URLEncodedFormDecoder? = nil,
            urlEncodedFormEncoder: URLEncodedFormEncoder? = nil
        ) {
            self.graphQLJSONEncoder = graphQLJSONEncoder ?? defaultGraphQLJSONEncoder
            self.jsonDecoder = jsonDecoder ?? defaultJSONDecoder
            self.jsonEncoder = jsonEncoder ?? defaultJSONEncoder
            self.urlEncodedFormDecoder = urlEncodedFormDecoder ?? defaultURLEncodedFormDecoder
            self.urlEncodedFormEncoder = urlEncodedFormEncoder ?? defaultURLEncodedFormEncoder
        }
    }

    public struct IDE: Sendable, Equatable {
        /// GraphiQL: https://github.com/graphql/graphiql
        public static var graphiql: Self {
            .init(type: .graphiql)
        }

        /// Do not expose a GraphQL IDE
        public static var none: Self {
            .init(type: .none)
        }

        let type: IDEType
        enum IDEType {
            case graphiql
            case none
        }
    }

    public struct SubscriptionProtocol: Sendable, Hashable {
        /// Expose GraphQL subscriptions over WebSockets
        public static var websocket: Self {
            .init(type: .websocket)
        }

        let type: SubscriptionProtocolType
        enum SubscriptionProtocolType {
            case websocket
        }
    }

    public struct WebSocket: Sendable {
        let onWebSocketInit: @Sendable (WebSocketInit) async throws -> Void

        /// GraphQL over WebSocket configuration
        /// - Parameter onWebSocketInit: A custom callback run during `connection_init` resolution that allows
        /// authorization using the `payload` field of the `connection_init` message.
        /// Throw from this closure to indicate that authorization has failed.
        public init(
            onWebSocketInit: @Sendable @escaping (WebSocketInit) async throws -> Void = { (_: EmptyWebSocketInit) in }
        ) {
            self.onWebSocketInit = onWebSocketInit
        }
    }
}

let defaultGraphQLJSONEncoder: GraphQLJSONEncoder = {
    let encoder = GraphQLJSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

let defaultJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

let defaultJSONEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

let defaultURLEncodedFormDecoder: URLEncodedFormDecoder = {
    var decoder = URLEncodedFormDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

let defaultURLEncodedFormEncoder: URLEncodedFormEncoder = {
    var encoder = URLEncodedFormEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()
