import Foundation
import GraphQL
import HTTPTypes
import Hummingbird
import NIOCore

extension GraphQLHandler {
    /// https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#get
    func handleGet(request: Request, context: Context) async throws -> Response {
        guard config.allowGet else {
            throw HTTPError(.methodNotAllowed, message: "GET requests are disallowed")
        }

        // Decode query parameters as GraphQLRequest
        let graphQLRequest = try request.uri.decodeQuery(as: GraphQLRequest.self, context: context)

        let operationType: OperationType
        do {
            operationType = try graphQLRequest.operationType()
        } catch {
            // Indicates a request parsing error
            throw HTTPError(.badRequest, message: error.localizedDescription)
        }
        guard operationType != .mutation else {
            throw HTTPError(.methodNotAllowed, message: "Mutations using GET are disallowed")
        }
        let graphQLContextComputationInputs = GraphQLContextComputationInputs<Context>(
            hummingbirdRequest: request,
            hummingbirdContext: context,
            graphQLRequest: graphQLRequest
        )
        let graphQLContext = try await computeContext(graphQLContextComputationInputs)
        let result = await execute(
            graphQLRequest: graphQLRequest,
            context: graphQLContext,
            additionalValidationRules: config.additionalValidationRules
        )
        return try encodeResponse(result: result, request: request, context: context)
    }

    /// https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#post
    func handlePost(request: Request, context: Context) async throws -> Response {
        guard let contentType = request.headers[.contentType] else {
            throw HTTPError(.unsupportedMediaType, message: "Missing `Content-Type` header")
        }
        guard let mediaType = MediaType(from: contentType) else { throw HTTPError(.badRequest) }

        let graphQLRequest: GraphQLRequest
        switch mediaType {
        case .applicationJson, .applicationJsonGraphQL:
            do {
                graphQLRequest = try await config.coders.jsonDecoder.decode(GraphQLRequest.self, from: request, context: context)
            } catch {
                throw HTTPError(.badRequest, message: error.localizedDescription)
            }
        case .applicationUrlEncoded:
            do {
                graphQLRequest = try await config.coders.urlEncodedFormDecoder.decode(GraphQLRequest.self, from: request, context: context)
            } catch {
                throw HTTPError(.badRequest, message: error.localizedDescription)
            }
        default:
            throw HTTPError(.unsupportedMediaType)
        }

        let graphQLContextComputationInputs = GraphQLContextComputationInputs<Context>(
            hummingbirdRequest: request,
            hummingbirdContext: context,
            graphQLRequest: graphQLRequest
        )
        let graphQLContext = try await computeContext(graphQLContextComputationInputs)
        let result = await execute(
            graphQLRequest: graphQLRequest,
            context: graphQLContext,
            additionalValidationRules: config.additionalValidationRules
        )
        return try encodeResponse(result: result, request: request, context: context)
    }

    private func execute(
        graphQLRequest: GraphQLRequest,
        context: GraphQLContext,
        additionalValidationRules: [@Sendable (ValidationContext) -> Visitor]
    ) async -> GraphQLResult {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#validation
        let validationRules = GraphQL.specifiedRules + additionalValidationRules

        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#execution
        let result: GraphQLResult
        do {
            result = try await graphql(
                schema: schema,
                request: graphQLRequest.query,
                rootValue: rootValue,
                context: context,
                variableValues: graphQLRequest.variables,
                operationName: graphQLRequest.operationName,
                validationRules: validationRules
            )
        } catch let error as GraphQLError {
            // This indicates a request parsing error
            return GraphQLResult(data: nil, errors: [error])
        } catch {
            return GraphQLResult(data: nil, errors: [GraphQLError(message: error.localizedDescription)])
        }
        return result
    }

    /// https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#body
    private func encodeResponse(result: GraphQLResult, request: Request, context: Context) throws -> Response {
        let acceptHeader = request.headers[.accept]

        if !config.allowMissingAcceptHeader, acceptHeader == nil {
            throw HTTPError(.notAcceptable, message: "An `Accept` header must be provided")
        }

        let acceptedTypes = parseAcceptHeader(acceptHeader)

        // Try to respond with the best matching media type, in order
        for mediaType in acceptedTypes {
            if MediaType.applicationJsonGraphQL.isType(mediaType) {
                return try config.coders.graphQLJSONEncoder.encode(result, from: request, context: context)
            }
            if MediaType.applicationJson.isType(mediaType) {
                return try config.coders.jsonEncoder.encode(result, from: request, context: context)
            }
            if MediaType.applicationUrlEncoded.isType(mediaType) {
                return try config.coders.urlEncodedFormEncoder.encode(result, from: request, context: context)
            }
        }

        // Use the default if configured to do so
        if config.allowMissingAcceptHeader {
            return try config.coders.graphQLJSONEncoder.encode(result, from: request, context: context)
        }

        // Fail
        throw HTTPError(.notAcceptable)
    }

    private func parseAcceptHeader(_ header: String?) -> [MediaType] {
        guard let header = header else { return [] }

        return header
            .split(separator: ",")
            .compactMap { segment in
                MediaType(from: segment.trimmingCharacters(in: .whitespaces))
            }
    }
}
