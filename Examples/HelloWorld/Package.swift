// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HelloWorld",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "graphql-hummingbird", path: "../../"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
        .package(url: "https://github.com/GraphQLSwift/GraphQL.git", from: "4.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(
            url: "https://github.com/hummingbird-project/hummingbird-websocket.git",
            from: "2.0.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "HelloWorld",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "GraphQL", package: "GraphQL"),
                .product(name: "GraphQLHummingbird", package: "graphql-hummingbird"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        )
    ]
)
