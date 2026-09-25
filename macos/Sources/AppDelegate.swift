import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let server = BridgeServer()
    private let player = Player()
    private var statusItem: NSStatusItem!
    private var startError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pip", accessibilityDescription: "FloatTube")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        player.onReturnToTab = { [weak self] in self?.returnToTab() }
        player.onClose = { [weak self] in self?.closeByUser() }

        server.onMessage = { [weak self] message, reply in self?.handle(message, reply: reply) }
        do { try server.start() } catch { startError = error.localizedDescription }
    }

    // MARK: - Extensão

    private func handle(_ message: [String: Any], reply: @escaping ([String: Any]) -> Void) {
        switch message["type"] as? String {
        case "open":
            guard let request = PlayRequest(message) else { return reply(["ok": false, "error": "vídeo inválido"]) }
            player.open(request)
            reply(["ok": true])
        case "close":
            player.snapshot { [player] state in
                player.close()
                reply(state.merging(["ok": true]) { current, _ in current })
            }
        default: // hello / ping
            reply(["ok": true, "open": player.isOpen])
        }
    }

    /// Botão "voltar": a extensão foca a aba e ela mesma pede o fechamento com o tempo atual.
    private func returnToTab() {
        guard let tabId = player.current?.tabId, server.isConnected else { return closeAndOpenInBrowser() }
        server.send(event: ["type": "returnToTab", "tabId": tabId])
    }

    /// Fechado pelo X: a aba fica pausada, mas sincronizada no ponto em que o vídeo parou.
    private func closeByUser() {
        player.snapshot { [weak self] state in
            self?.player.close()
            guard state["tabId"] != nil else { return }
            self?.server.send(event: state.merging(["type": "closed"]) { current, _ in current })
        }
    }

    /// Sem aba de origem (link copiado ou extensão desconectada): continua o vídeo no navegador.
    private func closeAndOpenInBrowser() {
        player.snapshot { [weak self] state in
            self?.player.close()
            guard let id = state["videoId"] as? String else { return }
            let time = Int(state["time"] as? Double ?? 0)
            if let url = URL(string: "https://www.youtube.com/watch?v=\(id)&t=\(time)s") { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = startError ?? server.failure.map { "Erro no servidor local: \($0)" }
            ?? (server.isConnected ? "Extensão do Chrome conectada" : "Aguardando a extensão do Chrome")
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "")
        if let title = player.current?.title, player.isOpen {
            menu.addItem(withTitle: "▶︎ \(title.count > 48 ? String(title.prefix(47)) + "…" : title)", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        addItem(to: menu, "Abrir link do YouTube copiado", #selector(openFromClipboard))
        if player.isOpen {
            addItem(to: menu, "Voltar para a aba", #selector(returnToTabAction))
            addItem(to: menu, "Fechar player", #selector(closeAction))
        }
        menu.addItem(.separator())
        let pin = addItem(to: menu, "Fixar acima dos Spaces (não se mexe na troca)", #selector(togglePinning))
        pin.state = player.canPin && player.pinsAboveSpaces ? .on : .off
        if !player.canPin { pin.action = nil }
        let login = addItem(to: menu, "Abrir ao iniciar sessão", #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sair do FloatTube", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: text), let request = PlayRequest(url: url) else { return NSSound.beep() }
        player.open(request)
    }

    @objc private func returnToTabAction() { returnToTab() }
    @objc private func closeAction() { closeByUser() }
    @objc private func togglePinning() { player.pinsAboveSpaces.toggle() }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }
}
