import Foundation
import Network

/// Servidor WebSocket local (só 127.0.0.1) que conversa com a extensão do Chrome.
/// Recusa qualquer conexão cujo Origin não seja uma extensão, então sites não conseguem usá-lo.
final class BridgeServer {
    static let port: UInt16 = 38917

    /// Mensagem recebida; `reply` responde à mesma requisição (quando ela tem `id`).
    var onMessage: ((_ message: [String: Any], _ reply: @escaping ([String: Any]) -> Void) -> Void)?
    private(set) var failure: String?

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var pendingEvent: [String: Any]?

    var isConnected: Bool { !connections.isEmpty }

    func start() throws {
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        websocket.setClientRequestHandler(.main) { _, headers in
            let origin = headers.first { $0.name.caseInsensitiveCompare("Origin") == .orderedSame }?.value ?? ""
            return NWProtocolWebSocket.Response(status: origin.hasPrefix("chrome-extension://") ? .accept : .reject,
                                                subprotocol: nil)
        }
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)

        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state { self?.failure = error.localizedDescription }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: .main)
        self.listener = listener
    }

    /// Envia um evento para a extensão. Sem conexão, guarda o último e entrega quando ela reconectar.
    func send(event: [String: Any]) {
        guard isConnected else { pendingEvent = event; return }
        connections.forEach { send(event, to: $0) }
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                connections.append(connection)
                if let event = pendingEvent {
                    pendingEvent = nil
                    send(event, to: connection)
                }
            case .failed, .cancelled:
                drop(connection)
            default:
                break
            }
        }
        receive(on: connection)
        connection.start(queue: .main)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if let data,
               let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                if metadata.opcode == .close { return drop(connection) }
                if metadata.opcode == .text, let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let id = message["id"]
                    onMessage?(message) { [weak self] reply in
                        guard let id else { return }
                        var reply = reply
                        reply["id"] = id
                        self?.send(reply, to: connection)
                    }
                }
            }
            if error == nil { receive(on: connection) } else { drop(connection) }
        }
    }

    private func send(_ message: [String: Any], to connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        let context = NWConnection.ContentContext(identifier: "message",
                                                  metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func drop(_ connection: NWConnection) {
        connections.removeAll { $0 === connection }
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}
