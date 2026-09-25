import AppKit

/// Janela do player: proporção 16:9, cantos arredondados, sem barra de título visível.
/// É um painel "não ativador": clicar nele não ativa o app, então não rouba o foco do que
/// você está fazendo nem faz o macOS pular de Space.
///
/// O mouse é tratado aqui, antes do vídeo: clique no vídeo = play/pause, arrastar de qualquer
/// ponto move a janela e uma faixa larga nas bordas redimensiona. Durante anúncios os cliques
/// passam direto para o YouTube (para dar para clicar em "Pular anúncio").
final class PlayerPanel: NSPanel {
    static let autosaveName = "FloatTubePlayer"
    /// Modo padrão do macOS (como o PiP do Chrome): a janela entra em todos os desktops.
    static let allSpacesBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    /// Dentro do Space privado: não pertence a desktop nenhum, então nada a coloca de volta neles.
    static let pinnedBehavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle]

    private static let aspect: CGFloat = 16 / 9
    private static let minWidth: CGFloat = 256
    private static let largeFactor: CGFloat = 1.6
    /// Espessura da área de redimensionar nas bordas e, perto dos cantos, da área diagonal.
    private static let edgeReach: CGFloat = 8
    private static let cornerReach: CGFloat = 22

    let controls = PlayerControls()

    /// Durante anúncios: cliques no vídeo vão direto para o YouTube.
    var passesClicksToVideo = false

    private var gesture: Gesture?
    /// Largura antes de aumentar pelo botão; `nil` = tamanho normal.
    private var normalWidth: CGFloat?
    private var showingResizeCursor = false
    /// Destino da animação em andamento: um novo clique parte daqui, sem tranco.
    private var animationTarget: NSRect?

    private enum Gesture {
        /// Botão apertado sobre o vídeo: ainda não se sabe se é clique (vai pro YouTube) ou arrasto (move a janela).
        case pending(down: NSEvent, mouse: NSPoint, frame: NSRect)
        case moving(mouse: NSPoint, frame: NSRect)
        case resizing(handle: Handle, mouse: NSPoint, frame: NSRect)
    }

    /// Borda ou canto pego: x -1 esquerda / 1 direita, y -1 baixo / 1 cima, 0 = nenhum nesse eixo.
    private struct Handle {
        let x: Int
        let y: Int
    }

    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
                   styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isFloatingPanel = true
        level = .floating
        collectionBehavior = Self.allSpacesBehavior
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        backgroundColor = .black
        contentAspectRatio = NSSize(width: 16, height: 9)
        contentMinSize = NSSize(width: Self.minWidth, height: Self.minWidth / Self.aspect)

        let root = HoverView()
        for view in [content, controls] {
            view.frame = root.bounds
            view.autoresizingMask = [.width, .height]
        }
        root.addSubview(content)
        controls.onToggleSize = { [weak self] in self?.toggleSize() }
        root.addSubview(controls)
        root.onHover = { [weak self] inside in self?.controls.setVisible(inside) }
        contentView = root

        placeInitially()
        setFrameAutosaveName(Self.autosaveName)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Botão de tamanho: alterna entre o normal e um maior, crescendo a partir do canto da tela
    /// mais próximo para a janela não sair de onde você deixou.
    func toggleSize() {
        guard let area = visibleArea else { return }
        let current = animationTarget ?? frame
        let width: CGFloat
        if let normal = normalWidth {
            width = clampWidth(normal)
            normalWidth = nil
        } else {
            normalWidth = current.width
            width = clampWidth(current.width * Self.largeFactor)
        }
        let height = width / Self.aspect
        let x = current.midX > area.midX ? current.maxX - width : current.minX
        let y = current.midY < area.midY ? current.minY : current.maxY - height
        animate(to: keptOnScreen(NSRect(x: x, y: y, width: width, height: height), snap: false))
        controls.setLarge(normalWidth != nil)
    }

    /// Anima o frame desacelerando no fim (como as animações do sistema), em vez do pulo linear
    /// do `setFrame(_:display:animate:)`. Com "Reduzir movimento" ligado, muda direto.
    private func animate(to target: NSRect, duration: TimeInterval = 0.34) {
        guard target != frame else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return setFrame(target, display: true)
        }
        animationTarget = target
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            if self?.animationTarget == target { self?.animationTarget = nil }
        })
    }

    // MARK: - Mouse

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if beginGesture(event) { return }
        case .leftMouseDragged:
            if gesture != nil { return continueGesture() }
        case .leftMouseUp:
            if gesture != nil { return endGesture(event) }
        case .magnify:
            return pinch(event)
        case .mouseMoved:
            if showResizeCursor(at: event.locationInWindow) { return }
            // Fora de anúncio o vídeo não precisa do hover (e o YouTube mostraria coisas por cima).
            if !passesClicksToVideo { return }
        case .keyDown:
            if handleKey(event) { return }
        default:
            break
        }
        super.sendEvent(event)
    }

    private func beginGesture(_ event: NSEvent) -> Bool {
        let point = event.locationInWindow
        let mouse = NSEvent.mouseLocation
        if let handle = handle(at: point) {
            gesture = .resizing(handle: handle, mouse: mouse, frame: frame)
            return true
        }
        let hit = contentView?.hitTest(point)
        if hit is NSControl { return false }
        if let hit, hit.isDescendant(of: controls) {
            // Fundo de uma cápsula: só arrasta.
            gesture = .moving(mouse: mouse, frame: frame)
            NSCursor.closedHand.set()
            return true
        }
        gesture = .pending(down: event, mouse: mouse, frame: frame)
        return true
    }

    private func continueGesture() {
        let mouse = NSEvent.mouseLocation
        switch gesture {
        case .pending(_, let start, let startFrame):
            guard hypot(mouse.x - start.x, mouse.y - start.y) >= 4 else { return }
            gesture = .moving(mouse: start, frame: startFrame)
            NSCursor.closedHand.set()
            continueGesture()
        case .moving(let start, let startFrame):
            setFrameOrigin(NSPoint(x: startFrame.minX + mouse.x - start.x, y: startFrame.minY + mouse.y - start.y))
        case .resizing(let handle, let start, let startFrame):
            resize(from: startFrame, handle: handle, dx: mouse.x - start.x, dy: mouse.y - start.y)
        case nil:
            break
        }
    }

    private func endGesture(_ up: NSEvent) {
        let finished = gesture
        gesture = nil
        switch finished {
        case .pending(let down, _, _):
            // Foi só um clique: play/pause, ou, durante anúncio, entrega o clique ao YouTube.
            if passesClicksToVideo {
                super.sendEvent(down)
                super.sendEvent(up)
            } else {
                controls.onTogglePlay?()
            }
        case .moving:
            NSCursor.arrow.set()
            animate(to: keptOnScreen(frame, snap: true), duration: 0.28)
        case .resizing:
            finishManualResize()
        case nil:
            break
        }
    }

    /// Espaço: play/pause · ← →: 10 segundos · M: som.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 49: controls.onTogglePlay?()
        case 123: controls.onSeekBy?(-10)
        case 124: controls.onSeekBy?(10)
        case 46: controls.onToggleMute?()
        default: return false
        }
        return true
    }

    private func pinch(_ event: NSEvent) {
        let width = clampWidth(frame.width * (1 + event.magnification))
        let height = width / Self.aspect
        setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height), display: true)
        if event.phase == .ended || event.phase == .cancelled { finishManualResize() }
    }

    private func resize(from start: NSRect, handle: Handle, dx: CGFloat, dy: CGFloat) {
        let byWidth = start.width + dx * CGFloat(handle.x)
        let byHeight = (start.height + dy * CGFloat(handle.y)) * Self.aspect
        let width: CGFloat
        switch (handle.x != 0, handle.y != 0) {
        case (true, true): width = clampWidth(max(byWidth, byHeight))
        case (true, false): width = clampWidth(byWidth)
        default: width = clampWidth(byHeight)
        }
        let height = width / Self.aspect
        // O lado oposto ao que está sendo puxado fica parado; num eixo sem borda, cresce a partir do centro.
        let x = handle.x < 0 ? start.maxX - width : handle.x > 0 ? start.minX : start.midX - width / 2
        let y = handle.y < 0 ? start.maxY - height : handle.y > 0 ? start.minY : start.midY - height / 2
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    /// Tamanho escolhido à mão vira o novo "normal" do botão de tamanho.
    private func finishManualResize() {
        normalWidth = nil
        controls.setLarge(false)
        animate(to: keptOnScreen(frame, snap: false), duration: 0.28)
    }

    private func handle(at point: NSPoint) -> Handle? {
        func side(_ value: CGFloat, _ length: CGFloat, _ reach: CGFloat) -> Int {
            value < reach ? -1 : value > length - reach ? 1 : 0
        }
        var x = side(point.x, frame.width, Self.edgeReach)
        var y = side(point.y, frame.height, Self.edgeReach)
        guard x != 0 || y != 0 else { return nil }
        // Perto de um canto, pegar numa das bordas já redimensiona na diagonal.
        if x == 0 { x = side(point.x, frame.width, Self.cornerReach) }
        if y == 0 { y = side(point.y, frame.height, Self.cornerReach) }
        return Handle(x: x, y: y)
    }

    private func showResizeCursor(at point: NSPoint) -> Bool {
        guard gesture == nil, let handle = handle(at: point) else {
            if showingResizeCursor, gesture == nil { NSCursor.arrow.set() }
            showingResizeCursor = false
            return false
        }
        cursor(for: handle).set()
        showingResizeCursor = true
        return true
    }

    private func cursor(for handle: Handle) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch (handle.x, handle.y) {
            case (-1, 1): position = .topLeft
            case (1, 1): position = .topRight
            case (-1, -1): position = .bottomLeft
            case (1, -1): position = .bottomRight
            case (-1, _): position = .left
            case (1, _): position = .right
            case (_, 1): position = .top
            default: position = .bottom
            }
            return .frameResize(position: position, directions: .all)
        }
        return handle.y == 0 ? .resizeLeftRight : handle.x == 0 ? .resizeUpDown : .crosshair
    }

    // MARK: - Geometria

    private var visibleArea: NSRect? { (screen ?? NSScreen.main)?.visibleFrame }

    private func clampWidth(_ width: CGFloat) -> CGFloat {
        guard let area = visibleArea else { return max(width, Self.minWidth) }
        let maxWidth = min(area.width, area.height * Self.aspect) * 0.95
        return min(max(width, Self.minWidth), maxWidth)
    }

    /// Mantém a janela inteira na tela; com `snap`, gruda nas bordas quando solta perto delas.
    private func keptOnScreen(_ rect: NSRect, snap: Bool) -> NSRect {
        guard let area = visibleArea else { return rect }
        var target = rect
        if snap {
            let margin: CGFloat = 12, reach: CGFloat = 40
            if target.minX - area.minX < reach { target.origin.x = area.minX + margin }
            if area.maxX - target.maxX < reach { target.origin.x = area.maxX - margin - target.width }
            if target.minY - area.minY < reach { target.origin.y = area.minY + margin }
            if area.maxY - target.maxY < reach { target.origin.y = area.maxY - margin - target.height }
        }
        target.origin.x = min(max(target.minX, area.minX), area.maxX - target.width)
        target.origin.y = min(max(target.minY, area.minY), area.maxY - target.height)
        return target
    }

    /// Primeira vez: canto inferior direito da tela onde está o mouse. Depois, a última posição usada.
    private func placeInitially() {
        if setFrameUsingName(Self.autosaveName) { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let size = NSSize(width: 480, height: 270)
        setFrame(NSRect(x: area.maxX - size.width - 20, y: area.minY + 20,
                        width: size.width, height: size.height), display: false)
    }
}

final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
