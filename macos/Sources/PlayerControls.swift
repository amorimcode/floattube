import AppKit

/// Controles nativos em Liquid Glass sobre o vídeo, no estilo do PiP do sistema. Os controles do
/// YouTube ficam escondidos: assim nada se sobrepõe e dá para arrastar a janela por qualquer ponto.
///
/// Só os botões e a barra de progresso recebem cliques; o resto da área deixa o mouse passar para
/// a janela (clique no vídeo = play/pause, arrastar = mover).
final class PlayerControls: NSView {
    struct State {
        var time: Double = 0
        var duration: Double = 0
        var playing = false
        var ended = false
        var muted = false
    }

    var onClose: (() -> Void)?
    var onToggleSize: (() -> Void)?
    var onReturn: (() -> Void)?
    var onTogglePlay: (() -> Void)?
    var onSeekBy: ((Double) -> Void)?
    var onSeekTo: ((Double) -> Void)?
    var onToggleMute: (() -> Void)?
    /// O Player só consulta o tempo do vídeo enquanto os controles estão visíveis.
    var onVisibilityChange: ((Bool) -> Void)?

    private(set) var isShown = false

    /// Durante anúncios só a cápsula de cima aparece, para não cobrir o "Pular anúncio" do YouTube.
    var adShowing = false {
        didSet { applyAdMode() }
    }

    private lazy var sizeButton = ActionButton(symbol: "arrow.up.left.and.arrow.down.right", tip: "Aumentar", size: 12) { [weak self] in
        self?.onToggleSize?()
    }
    private lazy var playButton = ActionButton(symbol: "play.fill", tip: "Reproduzir", size: 24) { [weak self] in
        self?.onTogglePlay?()
    }
    private lazy var muteButton = ActionButton(symbol: "speaker.wave.2.fill", tip: "Sem som", size: 12) { [weak self] in
        self?.onToggleMute?()
    }
    private let slider = GlassSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let elapsed = PlayerControls.timeLabel()
    private let remaining = PlayerControls.timeLabel()
    private var middle: NSView!
    private var bottom: NSView!
    private var scrubbing = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        appearance = NSAppearance(named: .darkAqua)

        let close = ActionButton(symbol: "xmark", tip: "Fechar", size: 12) { [weak self] in self?.onClose?() }
        let back = ActionButton(symbol: "pip.exit", tip: "Voltar para a aba", size: 12) { [weak self] in self?.onReturn?() }
        let backward = ActionButton(symbol: "gobackward.10", tip: "Voltar 10 segundos", size: 17) { [weak self] in self?.onSeekBy?(-10) }
        let forward = ActionButton(symbol: "goforward.10", tip: "Avançar 10 segundos", size: 17) { [weak self] in self?.onSeekBy?(10) }

        slider.target = self
        slider.action = #selector(scrub)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let top = Self.capsule([close, sizeButton, back], spacing: 14, inset: 12, height: 28)
        middle = Self.capsule([backward, playButton, forward], spacing: 22, inset: 18, height: 44)
        bottom = Self.capsule([muteButton, elapsed, slider, remaining], spacing: 8, inset: 12, height: 28)
        for view in [top, middle!, bottom!] { addSubview(view) }

        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            top.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            middle.centerXAnchor.constraint(equalTo: centerXAnchor),
            middle.centerYAnchor.constraint(equalTo: centerYAnchor),
            bottom.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            bottom.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não suportado") }

    func setVisible(_ visible: Bool) {
        guard visible != isShown else { return }
        isShown = visible
        onVisibilityChange?(visible)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? 0.18 : 0.3
            animator().alphaValue = visible ? 1 : 0
        }
    }

    func setLarge(_ large: Bool) {
        sizeButton.setSymbol(large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                             tip: large ? "Diminuir" : "Aumentar")
    }

    func update(_ state: State) {
        playButton.setSymbol(state.playing ? "pause.fill" : state.ended ? "arrow.counterclockwise" : "play.fill",
                             tip: state.playing ? "Pausar" : "Reproduzir")
        muteButton.setSymbol(state.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                             tip: state.muted ? "Com som" : "Sem som")
        guard !scrubbing else { return }
        slider.maxValue = max(state.duration, 1)
        slider.doubleValue = state.time
        elapsed.stringValue = Self.format(state.time)
        remaining.stringValue = "-" + Self.format(max(0, state.duration - state.time))
    }

    // Só os controles recebem o mouse; o resto passa para a janela.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard alphaValue > 0.01, let hit = super.hitTest(point), hit !== self else { return nil }
        return hit
    }

    @objc private func scrub() {
        let type = NSApp.currentEvent?.type
        scrubbing = type == .leftMouseDown || type == .leftMouseDragged
        elapsed.stringValue = Self.format(slider.doubleValue)
        onSeekTo?(slider.doubleValue)
    }

    private func applyAdMode() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            middle.animator().alphaValue = adShowing ? 0 : 1
            bottom.animator().alphaValue = adShowing ? 0 : 1
        }
        middle.isHidden = false
        bottom.isHidden = false
        // Escondidos também para cliques: `isHidden` depois do fade.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            middle.isHidden = adShowing
            bottom.isHidden = adShowing
        }
    }

    /// Cápsula de Liquid Glass (macOS 26+), no estilo "clear" que a Apple usa sobre vídeo.
    /// Em versões antigas, um desfoque comum no mesmo formato.
    private static func capsule(_ views: [NSView], spacing: CGFloat, inset: CGFloat, height: CGFloat) -> NSView {
        let stack = NSStackView(views: views)
        stack.spacing = spacing
        stack.edgeInsets = NSEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        let capsule: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear
            glass.cornerRadius = height / 2
            glass.contentView = stack
            capsule = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.blendingMode = .withinWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = height / 2
            blur.layer?.masksToBounds = true
            stack.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
                stack.topAnchor.constraint(equalTo: blur.topAnchor),
                stack.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            ])
            capsule = blur
        }
        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.heightAnchor.constraint(equalToConstant: height).isActive = true
        return capsule
    }

    private static func timeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "0:00")
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds.isFinite ? max(0, seconds) : 0)
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

final class ActionButton: NSButton {
    private let handler: () -> Void
    private let pointSize: CGFloat
    private var symbol: String?

    init(symbol: String, tip: String, size: CGFloat, handler: @escaping () -> Void) {
        self.handler = handler
        self.pointSize = size
        super.init(frame: .zero)
        contentTintColor = .white
        isBordered = false
        target = self
        action = #selector(fire)
        setSymbol(symbol, tip: tip)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não suportado") }

    func setSymbol(_ symbol: String, tip: String) {
        guard symbol != self.symbol else { return }
        self.symbol = symbol
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .semibold))
        toolTip = tip
    }

    @objc private func fire() { handler() }

    // Funciona no primeiro clique, mesmo com a janela inativa.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class GlassSlider: NSSlider {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
