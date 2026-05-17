import GraphQLTransportWS
import GraphQLWS
import HummingbirdWebSocket
import Logging
import NIOCore
import NIOFoundationCompat

import struct Foundation.Data

/// Messenger wrapper for WebSockets
class WebSocketMessenger: GraphQLTransportWS.Messenger, GraphQLWS.Messenger, @unchecked Sendable {
    private let outbound: WebSocketOutboundWriter
    private let logger: Logger

    init(
        outbound: WebSocketOutboundWriter,
        logger: Logger
    ) {
        self.outbound = outbound
        self.logger = logger
    }

    func send(_ message: Data) async throws {
        try await outbound.withTextMessageWriter { writer in
            try await writer.callAsFunction(ByteBuffer(data: message))
        }
        logger.trace("GraphQL server sent: \(String(decoding: message, as: UTF8.self))")
    }

    func error(_ message: String, code: Int) async throws {
        try await outbound.close(.init(codeNumber: code), reason: message)
    }

    func close() async throws {
        try await outbound.close(.goingAway, reason: nil)
    }
}
