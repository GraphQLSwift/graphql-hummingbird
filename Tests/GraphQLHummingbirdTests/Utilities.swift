import GraphQL
import Hummingbird

let jsonGraphQLHeaders: HTTPFields = [
    .accept: MediaType.applicationJsonGraphQL.description,
    .contentType: MediaType.applicationJsonGraphQL.description,
]

let jsonHeaders: HTTPFields = [
    .accept: MediaType.applicationJson.description,
    .contentType: MediaType.applicationJson.description,
]

let helloWorldSchema = try! GraphQLSchema(
    query: GraphQLObjectType(
        name: "Query",
        fields: [
            "hello": GraphQLField(
                type: GraphQLString,
                args: [
                    "name": GraphQLArgument(type: GraphQLString)
                ],
                resolve: { _, args, _, _ in
                    guard let name = args["name"].string else {
                        return "World"
                    }
                    return "Hello, \(name)"
                }
            )
        ]
    )
)

struct EmptyContext: Sendable {}
