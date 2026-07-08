import Foundation
import GraphQL
import HTTPTypes
import Hummingbird
import NIOCore

extension GraphQLHandler {
    /// https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#get
    func handleGet(request: Request, context: Context, jsonDecoder: JSONDecoder) async throws
        -> Response
    {
        guard config.allowGet else {
            throw HTTPError(.methodNotAllowed, message: "GET requests are disallowed")
        }

        // Decode query parameters as GraphQLRequest
        let queryParameters = request.uri.queryParameters
        guard let query = queryParameters.get("query") else {
            throw HTTPError(.badRequest, message: "`query` parameter is required")
        }
        let variables: [String: Map]
        if let queryVariables = queryParameters.get("variables") {
            do {
                variables = try jsonDecoder.decode(
                    [String: Map].self,
                    from: Data(queryVariables.utf8)
                )
            } catch {
                throw HTTPError(
                    .badRequest,
                    message: "`variable` parameter could not be decoded: \(error)"
                )
            }
        } else {
            variables = [:]
        }
        let graphQLRequest = GraphQLRequest(
            query: query,
            operationName: queryParameters.get("operationName"),
            variables: variables
        )

        let documentAST: Document
        let operationType: OperationType
        do {
            documentAST = try parse(
                source: Source(body: graphQLRequest.query, name: graphQLRequest.operationName ?? "")
            )
            operationType = try Self.operationTypeOf(
                document: documentAST,
                named: graphQLRequest.operationName
            )
        } catch {
            // Indicates a request parsing error
            throw HTTPError(.badRequest, message: error.localizedDescription)
        }
        guard operationType != .mutation else {
            throw HTTPError(.methodNotAllowed, message: "Mutations using GET are disallowed")
        }
        let graphQLContextComputationInputs = GraphQLContextComputationInputs<
            Context, WebSocketInitResult
        >(
            hummingbirdRequest: request,
            hummingbirdContext: context,
            graphQLRequest: graphQLRequest,
            websocketInitResult: nil
        )
        let graphQLContext = try await computeContext(graphQLContextComputationInputs)
        let result = await execute(
            documentAST: documentAST,
            operationName: graphQLRequest.operationName,
            variables: graphQLRequest.variables,
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
                graphQLRequest = try await config.coders.jsonDecoder.decode(
                    GraphQLRequest.self,
                    from: request,
                    context: context
                )
            } catch {
                throw HTTPError(.badRequest, message: error.localizedDescription)
            }
        case .applicationUrlEncoded:
            do {
                graphQLRequest = try await config.coders.urlEncodedFormDecoder.decode(
                    GraphQLRequest.self,
                    from: request,
                    context: context
                )
            } catch {
                throw HTTPError(.badRequest, message: error.localizedDescription)
            }
        default:
            throw HTTPError(.unsupportedMediaType)
        }

        let documentAST: Document
        do {
            documentAST = try parse(
                source: Source(body: graphQLRequest.query, name: graphQLRequest.operationName ?? "")
            )
        } catch let error as GraphQLError {
            // Indicates a request parsing error
            let result = GraphQLResult(data: nil, errors: [error])
            return try encodeResponse(result: result, request: request, context: context)
        }

        let graphQLContextComputationInputs = GraphQLContextComputationInputs<
            Context, WebSocketInitResult
        >(
            hummingbirdRequest: request,
            hummingbirdContext: context,
            graphQLRequest: graphQLRequest,
            websocketInitResult: nil
        )
        let graphQLContext = try await computeContext(graphQLContextComputationInputs)
        let result = await execute(
            documentAST: documentAST,
            operationName: graphQLRequest.operationName,
            variables: graphQLRequest.variables,
            context: graphQLContext,
            additionalValidationRules: config.additionalValidationRules
        )
        return try encodeResponse(result: result, request: request, context: context)
    }

    private func execute(
        documentAST: Document,
        operationName: String?,
        variables: [String: Map],
        context: GraphQLContext,
        additionalValidationRules: [@Sendable (ValidationContext) -> Visitor]
    ) async -> GraphQLResult {
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#validation

        // Validate schema
        let schemaValidationErrors = validateSchema(schema: schema)
        guard schemaValidationErrors.isEmpty else {
            return GraphQLResult(errors: schemaValidationErrors)
        }

        // Validate request
        let validationRules = GraphQL.specifiedRules + additionalValidationRules
        let validationErrors = validate(
            schema: schema,
            ast: documentAST,
            rules: validationRules
        )
        guard validationErrors.isEmpty else {
            return GraphQLResult(errors: validationErrors)
        }

        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#execution
        let result: GraphQLResult
        do {
            result = try await GraphQL.execute(
                schema: schema,
                documentAST: documentAST,
                rootValue: rootValue,
                context: context,
                variableValues: variables,
                operationName: operationName
            )
        } catch let error as GraphQLError {
            // This indicates a request parsing error
            return GraphQLResult(data: nil, errors: [error])
        } catch {
            return GraphQLResult(
                data: nil,
                errors: [GraphQLError(message: error.localizedDescription)]
            )
        }
        return result
    }

    /// https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#body
    private func encodeResponse(result: GraphQLResult, request: Request, context: Context) throws
        -> Response
    {
        let acceptHeader = request.headers[.accept]

        if !config.allowMissingAcceptHeader, acceptHeader == nil {
            throw HTTPError(.notAcceptable, message: "An `Accept` header must be provided")
        }

        let acceptedTypes = parseAcceptHeader(acceptHeader)

        // Try to respond with the best matching media type, in order
        for mediaType in acceptedTypes {
            if MediaType.applicationJsonGraphQL.isType(mediaType) {
                return try config.coders.graphQLJSONEncoder.encode(
                    result,
                    from: request,
                    context: context
                )
            }
            if MediaType.applicationJson.isType(mediaType) {
                return try config.coders.jsonEncoder.encode(result, from: request, context: context)
            }
            if MediaType.applicationUrlEncoded.isType(mediaType) {
                return try config.coders.urlEncodedFormEncoder.encode(
                    result,
                    from: request,
                    context: context
                )
            }
        }

        // Use the default if configured to do so
        if config.allowMissingAcceptHeader {
            return try config.coders.graphQLJSONEncoder.encode(
                result,
                from: request,
                context: context
            )
        }

        // Fail
        throw HTTPError(.notAcceptable)
    }

    private func parseAcceptHeader(_ header: String?) -> [MediaType] {
        guard let header = header else { return [] }

        return
            header
            .split(separator: ",")
            .compactMap { segment in
                MediaType(from: segment.trimmingCharacters(in: .whitespaces))
            }
    }

    private static func operationTypeOf(
        document: Document,
        named operationName: String? = nil
    ) throws -> OperationType {
        let operationDefinitions = document.definitions.filter { operation in
            operation.kind == .operationDefinition
        }.compactMap { operation in
            operation as? OperationDefinition
        }

        // We don't have to validate the document and check for multiple/missing operations here
        // That will be done upon execution.
        let operationMatch = operationDefinitions.first { operation in
            if let operationName {
                return operationName == operation.name?.value
            } else {
                return true
            }
        }
        return operationMatch?.operation ?? .query
    }
}
