import GraphQL
import Hummingbird

extension GraphQLJSONEncoder: @retroactive ResponseEncoder {
    /// Extend GraphQLJSONEncoder to support generating a ``HummingbirdCore/Response``. Sets body and header values
    /// - Parameters:
    ///   - value: Value to encode
    ///   - request: Request used to generate response
    ///   - context: Request context
    public func encode(_ value: some Encodable, from request: Request, context: some RequestContext)
        throws -> Response
    {
        try encode(value, status: .ok, from: request, context: context)
    }
}

extension GraphQLJSONEncoder {
    /// Extend GraphQLJSONEncoder to support generating a ``HummingbirdCore/Response``. Sets body and header values. Similar to the
    /// `ResponseEncoder`-required version, except it allows setting the reponse status as well.
    /// - Parameters:
    ///   - value: Value to encode
    ///   - status: The status of the response
    ///   - request: Request used to generate response
    ///   - context: Request context
    func encode(
        _ value: some Encodable,
        status: HTTPResponse.Status,
        from _: Request,
        context _: some RequestContext
    ) throws -> Response {
        let data = try encode(value)
        let buffer = ByteBuffer(bytes: data)
        return Response(
            status: status,
            headers: [
                .contentType: "\(MediaType.applicationJsonGraphQL); charset=utf-8",
                .contentLength: data.count.description,
            ],
            body: .init(byteBuffer: buffer)
        )
    }
}

extension GraphQLJSONEncoder {
    /// Overload for GraphQLJSONEncoder to support generating a ``HummingbirdCore/Response`` from a GraphQLResult. Sets body, headers, and status, according to [GraphQL-over-HTTP spec](https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#applicationgraphql-responsejson).
    /// - Parameters:
    ///   - value: GraphQLResult to encode
    ///   - request: Request used to generate response
    ///   - context: Request context
    func encode(_ value: GraphQLResult, from request: Request, context: some RequestContext) throws
        -> Response
    {
        var status = HTTPResponse.Status.ok
        // We must return `bad request` with the content if there were failures preventing a partial result
        // https://github.com/graphql/graphql-over-http/blob/main/spec/GraphQLOverHTTP.md#applicationgraphql-responsejson
        if value.data == nil {
            status = .badRequest
        }
        return try encode(value, status: status, from: request, context: context)
    }
}
