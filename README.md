# GraphQLHummingbird

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FGraphQLSwift%2Fgraphql-hummingbird%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/GraphQLSwift/graphql-hummingbird)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FGraphQLSwift%2Fgraphql-hummingbird%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/GraphQLSwift/graphql-hummingbird)

> ***WARNING***: This package is in v0.x beta. It's API is still evolving and is subject to breaking changes in minor version bumps.

A Swift library for integrating [GraphQL](https://github.com/GraphQLSwift/GraphQL) with [Hummingbird](https://github.com/hummingbird-project/hummingbird), enabling you to easily expose GraphQL APIs in your Hummingbird applications.

## Features

- Simple integration of GraphQL schemas with Hummingbird routing
- Compatibility with the [GraphQL over HTTP spec](https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md)
- Subscription support using WebSockets, with support for [`graphql-transport-ws`](https://github.com/GraphQLSwift/GraphQLTransportWS) and [`graphql-ws`](https://github.com/apollographql/subscriptions-transport-ws/blob/master/PROTOCOL.md) subprotocols
- Built-in [GraphiQL](https://github.com/graphql/graphiql) IDE

## Installation

Add GraphQLHummingbird as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/NeedleInAJayStack/graphql-hummingbird.git", from: "1.0.0"),
]
```

Then add it to your target:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "GraphQLHummingbird", package: "graphql-hummingbird"),
    ]
)
```

## Usage

See [the HelloWorld project](https://github.com/GraphQLSwift/graphql-hummingbird/tree/main/Examples/HelloWorld) for a full working example.

### Basic Example

```swift
import GraphQL
import GraphQLHummingbird
import Hummingbird

// Define your GraphQL schema
// To construct schemas, consider using `Graphiti` or `graphql-generator`
let schema = try GraphQLSchema(
    query: GraphQLObjectType(
        name: "Query",
        fields: [
            "hello": GraphQLField(
                type: GraphQLString,
                resolve: { _, _, _, _ in
                    "World"
                }
            )
        ]
    )
)

// Define your Context
struct GraphQLContext: Sendable {}

// Create router and register GraphQL
let router = Router()
router.graphql(schema: schema) { _ in
    return GraphQLContext()
}

// Create and run the application
let app = Application(
    router: router,
    configuration: .init(address: .hostname("127.0.0.1", port: 8080))
)
try await app.runService()
```

That's it! You can now view the GraphiQL IDE at http://localhost:8080/graphql, or query directly using `GET` or `POST`:

```bash
curl -X POST http://localhost:8080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ hello }"}'
```

Response:
```json
{
  "data": {
    "hello": "World"
  }
}
```

See the `graphql` function documentation for advanced configuration options.

### Computing GraphQL Context

The required closure in the `graphql` function is used to compute the `GraphQLContext` object, which is injected into each GraphQL resolver. The `inputs` argument passes in data from the request so that the Context can be created dynamically:

```swift
router.graphql(schema: schema) { inputs in
    return GraphQLContext(
        userID: inputs.hummingbirdContext.userID,
        logger: inputs.hummingbirdContext.logger,
        debug: inputs.hummingbirdRequest.headers[.init("debug")!] != nil,
        operationName: inputs.graphQLRequest.operationName
    )
}
```

### WebSockets

Subscription support via WebSockets can be enabled by calling the `graphqlWebSocket` function on a `Router` whose context conforms to `WebSocketRequestContext`, from the `HummingbirdWebSocket` package:

```swift
import GraphQL
import GraphQLHummingbird
import Hummingbird
import HummingbirdWebSocket

struct MyWebSocketContext: WebSocketRequestContext, RequestContext {
    ...
}

let router = Router(context: MyContext.self)
router.graphql(schema: schema) { _ in
    GraphQLContext()
}
let webSocketRouter = Router(context: MyWebSocketContext.self)
webSocketRouter.graphqlWebSocket(schema: schema) { _, _ in
    GraphQLContext()
}
let app = Application(
    router: router,
    server: .http1WebSocketUpgrade(webSocketRouter: webSocketRouter)
)
```

The example above follows Hummingbird best practices when it uses a separate router for HTTP and WebSocket requests. For more details, see the [Hummingbird WebSocket documentation](https://docs.hummingbird.codes/2.0/documentation/hummingbird/websocketserverupgrade#Overview).

### Custom Encoding/Decoding

You can set custom encoders and decoders using the `Config.coders` argument:

```swift
// Configure custom JSON encoder
let graphQLJSONEncoder = GraphQLJSONEncoder()
graphQLJSONEncoder.dateEncodingStrategy = .millisecondsSince1970

// Inject it using the `config.coders` argument
router.graphql(
    schema: schema,
    config: .init(
        coders: .init(graphQLJSONEncoder: graphQLJSONEncoder)
    )
) { _ in
    GraphQLContext()
}
```

Like [Hummingbird](https://docs.hummingbird.codes/2.0/documentation/hummingbird/responseencoding#Date-encoding), all default GraphQL encoders and decoders use the standard settings with ISO8601 date formatting.
