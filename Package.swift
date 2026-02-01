// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GraphQLHummingbird",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "GraphQLHummingbird",
            targets: ["GraphQLHummingbird"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/GraphQLSwift/GraphQL.git", from: "4.0.0"),
        .package(url: "https://github.com/GraphQLSwift/GraphQLTransportWS.git", from: "0.2.1"),
        .package(url: "https://github.com/GraphQLSwift/GraphQLWS.git", from: "0.2.1"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "GraphQLHummingbird",
            dependencies: [
                .product(name: "GraphQL", package: "GraphQL"),
                .product(name: "GraphQLTransportWS", package: "GraphQLTransportWS"),
                .product(name: "GraphQLWS", package: "GraphQLWS"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        ),
        .testTarget(
            name: "GraphQLHummingbirdTests",
            dependencies: [
                "GraphQLHummingbird",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                .product(name: "HummingbirdWSTesting", package: "hummingbird-websocket"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ]
        ),
    ]
)
