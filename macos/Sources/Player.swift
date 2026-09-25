import AppKit
import WebKit

/// Vídeo a tocar no player flutuante (vindo da extensão ou de um link copiado).
struct PlayRequest {
    var videoId: String
    var list: String?
    var time: Double
    var rate: Double
    var volume: Int
    var muted: Bool
    var tabId: Int?
    var title: String?

    init?(_ message: [String: Any]) {
        guard let id = message["videoId"] as? String, Self.matches(id, "^[A-Za-z0-9_-]{11}$") else { return nil }
        videoId = id
        list = (message["list"] as? String).flatMap { Self.matches($0, "^[A-Za-z0-9_-]{2,64}$") ? $0 : nil }
        time = max(0, message["time"] as? Double ?? 0)
        rate = message["rate"] as? Double ?? 1
        volume = message["volume"] as? Int ?? 100
        muted = message["muted"] as? Bool ?? false
        tabId = message["tabId"] as? Int
        title = message["title"] as? String
    }

    /// youtube.com/watch?v=…, youtu.be/…, /shorts/…, /live/…, /embed/… (com `t=` e `list=` opcionais).
    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host?.lowercased() else { return nil }
        var query: [String: String] = [:]
        for item in parts.queryItems ?? [] where query[item.name] == nil { query[item.name] = item.value ?? "" }
        let path = url.pathComponents.filter { $0 != "/" }

        var id: String?
        if host == "youtu.be" {
            id = path.first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if path.first == "watch" { id = query["v"] }
            else if path.count >= 2, ["shorts", "live", "embed"].contains(path[0]) { id = path[1] }
        }
        guard let id else { return nil }

        var message: [String: Any] = ["videoId": id, "time": Self.seconds(query["t"] ?? query["start"] ?? "")]
        message["list"] = query["list"]
        self.init(message)
    }

    /// "90", "90s", "1m30s", "1h2m3s" → segundos.
    private static func seconds(_ text: String) -> Double {
        if let value = Double(text) { return value }
        var total = 0.0, digits = ""
        for character in text {
            if character.isNumber { digits.append(character); continue }
            let value = Double(digits) ?? 0
            digits = ""
            switch character {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: break
            }
        }
        return total + (Double(digits) ?? 0)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}

/// Player flutuante. Usa o player incorporado do YouTube (leve, se ajusta sozinho ao tamanho da
/// janela) e, se o vídeo não permitir incorporação, cai para a página do YouTube só com o vídeo.
/// Nos dois casos os controles do YouTube ficam escondidos e o app mostra os próprios, em Liquid
/// Glass, falando com o vídeo pelas funções `ftState()` e `ftCommand()` injetadas na página.
final class Player: NSObject {
    var onReturnToTab: (() -> Void)?
    var onClose: (() -> Void)?

    private(set) var current: PlayRequest?
    private(set) var usingWatchPage = false
    private var panel: PlayerPanel?
    private var stateTimer: Timer?
    private lazy var webView = makeWebView()
    private lazy var pinner = SpacePinner(level: UserDefaults.standard.object(forKey: "spaceLevel") as? Int ?? 1)

    var isOpen: Bool { panel?.isVisible == true }
    var canPin: Bool { pinner != nil }

    /// Coloca o player no Space privado (fica parado na troca de desktop). Desligado = comportamento
    /// padrão do macOS (janela em todos os desktops), útil para comparar.
    var pinsAboveSpaces: Bool {
        get { !UserDefaults.standard.bool(forKey: "disablePinning") }
        set {
            UserDefaults.standard.set(!newValue, forKey: "disablePinning")
            applyPinning()
        }
    }

    func open(_ request: PlayRequest) {
        current = request
        loadEmbed(request)
        let panel = panel ?? makePanel()
        if !panel.isVisible {
            panel.orderFrontRegardless()
            applyPinning()
        }
    }

    func close() {
        current = nil
        setAdShowing(false)
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        setPolling(false)
        webView.loadHTMLString("", baseURL: nil) // para o vídeo e libera o decodificador
    }

    /// Estado atual (tempo, se está tocando) para devolver o vídeo à aba no ponto certo.
    func snapshot(_ done: @escaping ([String: Any]) -> Void) {
        guard isOpen, let current else { return done([:]) }
        var result: [String: Any] = ["videoId": current.videoId]
        result["tabId"] = current.tabId
        webView.evaluateJavaScript(Self.stateScript) { [weak self] value, _ in
            if let state = value as? [String: Any] {
                result["time"] = state["time"]
                let code = state["state"] as? Int ?? -1
                result["playing"] = code == 1 || code == 3 // tocando ou carregando
                if let id = state["videoId"] as? String, !id.isEmpty { result["videoId"] = id }
            }
            if self?.usingWatchPage == true, let url = self?.webView.url,
               let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
                result["videoId"] = id
            }
            done(result)
        }
    }

    private func makePanel() -> PlayerPanel {
        let panel = PlayerPanel(content: webView)
        let controls = panel.controls
        controls.onReturn = { [weak self] in self?.onReturnToTab?() }
        controls.onClose = { [weak self] in self?.onClose?() }
        controls.onTogglePlay = { [weak self] in self?.command("'toggle'") }
        controls.onToggleMute = { [weak self] in self?.command("'toggleMute'") }
        controls.onSeekBy = { [weak self] seconds in self?.command("'seekBy', \(seconds)") }
        controls.onSeekTo = { [weak self] seconds in self?.command("'seekTo', \(seconds)") }
        controls.onVisibilityChange = { [weak self] visible in self?.setPolling(visible) }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeSpaceDidChange),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        self.panel = panel
        return panel
    }

    private func command(_ arguments: String) {
        webView.evaluateJavaScript("typeof ftCommand === 'function' && ftCommand(\(arguments))") { [weak self] _, _ in
            self?.refreshControls()
        }
    }

    /// Tempo e barra de progresso só são atualizados enquanto os controles estão visíveis.
    private func setPolling(_ active: Bool) {
        stateTimer?.invalidate()
        stateTimer = nil
        guard active else { return }
        refreshControls()
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.refreshControls() }
    }

    private func refreshControls() {
        guard let panel, isOpen else { return }
        webView.evaluateJavaScript(Self.stateScript) { value, _ in
            guard let state = value as? [String: Any] else { return }
            let code = state["state"] as? Int ?? -1
            panel.controls.update(.init(time: state["time"] as? Double ?? 0,
                                        duration: state["duration"] as? Double ?? 0,
                                        playing: code == 1 || code == 3,
                                        ended: code == 0,
                                        muted: state["muted"] as? Bool ?? false))
        }
    }

    private func setAdShowing(_ showing: Bool) {
        panel?.passesClicksToVideo = showing
        panel?.controls.adShowing = showing
    }

    private func applyPinning() {
        guard let panel, panel.isVisible, let pinner else { return }
        if pinsAboveSpaces {
            // Sem .canJoinAllSpaces: janela "em todos os desktops" é recolocada em cada desktop que
            // entra na tela e aparece como um fantasma deslizando junto na animação de troca.
            panel.collectionBehavior = PlayerPanel.pinnedBehavior
            pinner.pin(panel)
        } else {
            // Fora do Space privado a janela ficaria sem Space nenhum; reordenar faz o AppKit
            // colocá-la de volta nos desktops (todos, por causa do .canJoinAllSpaces).
            pinner.unpin(panel)
            panel.collectionBehavior = PlayerPanel.allSpacesBehavior
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    // Reforço: se algo recolocar a janela num desktop, ela volta a ficar só no Space privado.
    @objc private func activeSpaceDidChange() {
        if pinsAboveSpaces { applyPinning() }
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(self, name: "ft")
        config.userContentController.addUserScript(
            WKUserScript(source: Self.watchPageScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // Também dentro do iframe do YouTube (outra origem), por isso não é só no frame principal.
        config.userContentController.addUserScript(
            WKUserScript(source: Self.playerChromeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = Self.safariUserAgent
        view.setValue(false, forKey: "drawsBackground") // sem flash branco ao carregar
        view.navigationDelegate = self
        view.uiDelegate = self
        return view
    }

    private func loadEmbed(_ request: PlayRequest) {
        usingWatchPage = false
        var config: [String: Any] = ["videoId": request.videoId, "start": request.time, "rate": request.rate,
                                     "volume": request.volume, "muted": request.muted]
        config["list"] = request.list
        let json = (try? JSONSerialization.data(withJSONObject: config)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        // A origem vira o Referer do iframe; sem Referer o YouTube recusa o player (erro 153).
        webView.loadHTMLString(Self.embedHTML.replacingOccurrences(of: "__CONFIG__", with: json),
                               baseURL: URL(string: "https://com.amorim.floattube")!)
    }

    func loadWatchPage(_ request: PlayRequest) {
        usingWatchPage = true
        var parts = URLComponents(string: "https://www.youtube.com/watch")!
        parts.queryItems = [URLQueryItem(name: "v", value: request.videoId),
                            URLQueryItem(name: "t", value: "\(Int(request.time))s")]
        if let list = request.list { parts.queryItems?.append(URLQueryItem(name: "list", value: list)) }
        webView.load(URLRequest(url: parts.url!))
    }

    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    private static let embedHTML = """
    <!doctype html>
    <html><head><meta charset="utf-8">
    <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#player{position:fixed;inset:0;width:100%;height:100%;border:0}</style>
    </head><body><div id="player"></div>
    <script>
    const cfg = __CONFIG__;
    const post = (message) => webkit.messageHandlers.ft.postMessage(message);
    let player;
    function onYouTubeIframeAPIReady() {
      // Sem os controles do YouTube: o app desenha os próprios por cima.
      const vars = { autoplay: 1, controls: 0, disablekb: 1, fs: 0, iv_load_policy: 3, playsinline: 1, rel: 0,
                     start: Math.floor(cfg.start), origin: location.origin };
      if (cfg.list) { vars.listType = 'playlist'; vars.list = cfg.list; }
      player = new YT.Player('player', {
        videoId: cfg.videoId, width: '100%', height: '100%', playerVars: vars,
        events: {
          onReady: ({ target }) => {
            target.setVolume(cfg.volume);
            cfg.muted ? target.mute() : target.unMute();
            if (cfg.rate !== 1) target.setPlaybackRate(cfg.rate);
            target.playVideo();
          },
          onStateChange: () => post({ type: 'state' }),
          onError: ({ data }) => post({ type: 'error', code: data }),
        },
      });
    }
    function ftState() {
      if (!player || !player.getCurrentTime) return null;
      return { time: player.getCurrentTime(), duration: player.getDuration(), state: player.getPlayerState(),
               muted: player.isMuted(), videoId: (player.getVideoData() || {}).video_id };
    }
    function ftCommand(name, value) {
      if (!player || !player.getPlayerState) return;
      const state = player.getPlayerState();
      if (name === 'toggle') {
        if (state === 1 || state === 3) return player.pauseVideo();
        if (state === 0) player.seekTo(0, true);
        player.playVideo();
      } else if (name === 'seekBy') {
        player.seekTo(Math.max(0, player.getCurrentTime() + value), true);
      } else if (name === 'seekTo') {
        player.seekTo(value, true);
      } else if (name === 'toggleMute') {
        player.isMuted() ? player.unMute() : player.mute();
      }
    }
    </script>
    <script src="https://www.youtube.com/iframe_api"></script>
    </body></html>
    """

    /// Roda dentro do player do YouTube (no iframe do modo incorporado ou na página do modo reserva):
    /// esconde os controles do YouTube, exceto durante anúncios, e avisa o app quando um anúncio
    /// começa ou termina (aí os cliques passam direto, para dar para clicar em "Pular anúncio").
    private static let playerChromeScript = """
    if (/(^|\\.)youtube(-nocookie)?\\.com$/.test(location.hostname)) {
      const style = document.createElement('style');
      style.textContent = `html:not(.ft-ad) :is(.player-controls-top, .player-controls-middle,
        .player-controls-bottom, .ytmVideoInfoOverlay, .watch-on-youtube-button-wrapper,
        .action-menu-engagement-buttons-wrapper, .ytmCuedOverlayHost, .ytp-chrome-top, .ytp-chrome-bottom,
        .ytp-gradient-top, .ytp-gradient-bottom, .ytp-pause-overlay, .ytp-large-play-button,
        .ytp-endscreen-content, .ytp-ce-element) { display: none !important; }`;
      document.documentElement.appendChild(style);

      let adShowing = false;
      const report = (player) => {
        const showing = player.classList.contains('ad-showing');
        if (showing === adShowing) return;
        adShowing = showing;
        document.documentElement.classList.toggle('ft-ad', showing);
        webkit.messageHandlers.ft.postMessage({ type: 'ad', showing });
      };
      const watch = () => {
        const player = document.getElementById('movie_player');
        if (!player) return false;
        new MutationObserver(() => report(player)).observe(player, { attributes: true, attributeFilter: ['class'] });
        report(player);
        return true;
      };
      if (!watch()) {
        const finder = new MutationObserver(() => watch() && finder.disconnect());
        finder.observe(document.documentElement, { childList: true, subtree: true });
      }
    }
    """

    /// Só age em www.youtube.com (modo reserva): deixa apenas o player, ocupando a janela toda.
    private static let watchPageScript = """
    if (location.hostname === 'www.youtube.com') {
      const style = document.createElement('style');
      style.textContent = `
        html, body { overflow: hidden !important; background: #000 !important; }
        #masthead-container, #guide, tp-yt-app-drawer, ytd-mini-guide-renderer, #secondary, #below, #chat { display: none !important; }
        #movie_player { position: fixed !important; inset: 0 !important; width: 100vw !important; height: 100vh !important;
                        z-index: 2147483647 !important; background: #000 !important; }
        #movie_player video { width: 100% !important; height: 100% !important; top: 0 !important; left: 0 !important;
                              object-fit: contain !important; }
      `;
      document.documentElement.appendChild(style);

      const video = () => document.querySelector('#movie_player video') || document.querySelector('video');
      window.ftState = () => {
        const v = video();
        if (!v) return null;
        return { time: v.currentTime, duration: Number.isFinite(v.duration) ? v.duration : 0,
                 state: v.ended ? 0 : v.paused ? 2 : 1, muted: v.muted };
      };
      window.ftCommand = (name, value) => {
        const v = video();
        if (!v) return;
        if (name === 'toggle') v.paused || v.ended ? v.play() : v.pause();
        else if (name === 'seekBy') v.currentTime = Math.max(0, v.currentTime + value);
        else if (name === 'seekTo') v.currentTime = value;
        else if (name === 'toggleMute') v.muted = !v.muted;
      };
      for (const type of ['play', 'pause', 'ended']) {
        document.addEventListener(type, () => webkit.messageHandlers.ft.postMessage({ type: 'state' }), true);
      }

      const relayout = () => dispatchEvent(new Event('resize'));
      addEventListener('yt-navigate-finish', relayout);
      addEventListener('load', () => setTimeout(relayout, 500));
    }
    """

    private static let stateScript = "typeof ftState === 'function' ? ftState() : null"
}

extension Player: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch body["type"] as? String {
        case "state":
            refreshControls()
        case "ad":
            setAdShowing(body["showing"] as? Bool ?? false)
        case "error":
            guard !usingWatchPage, let current else { return }
            // 101/150: o dono do vídeo bloqueou a incorporação. Toca pela página do YouTube.
            NSLog("FloatTube: player incorporado falhou (código %@), usando a página do YouTube", "\(body["code"] ?? "?")")
            loadWatchPage(current)
        default:
            break
        }
    }
}

extension Player: WKNavigationDelegate, WKUIDelegate {
    // Links que tirariam o vídeo do player (logo, título, "Assistir no YouTube") abrem no navegador.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame != false, let url = action.request.url {
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }
}
