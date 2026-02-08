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
                resolve: { _, _, _, _ in
                    "World"
                }
            ),
        ]
    )
)

struct EmptyContext: Sendable {}
