import AppKit

/// Space privado do WindowServer, desenhado acima dos desktops do usuário.
///
/// Janelas comuns — mesmo com `.canJoinAllSpaces`, como o PiP do Chrome — pertencem aos Spaces
/// do usuário e entram na animação de troca de desktop: deslizam junto e "voltam" no fim.
/// Uma janela dentro deste Space não participa da transição, então fica parada no mesmo pixel
/// enquanto os desktops deslizam por baixo dela.
///
/// Usa a API privada do SkyLight (mesma técnica dos apps de "notch"). Se algum símbolo não
/// existir numa versão futura do macOS, `init` falha e o app volta ao comportamento padrão.
final class SpacePinner {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias SpaceCreateFn = @convention(c) (Int32, Int, CFDictionary?) -> UInt64
    private typealias SpaceLevelFn = @convention(c) (Int32, UInt64, Int) -> Void
    private typealias SpaceFn = @convention(c) (Int32, UInt64) -> Void
    private typealias SpacesFn = @convention(c) (Int32, CFArray) -> Void
    private typealias WindowsSpacesFn = @convention(c) (Int32, CFArray, CFArray) -> Void
    private typealias CopySpacesFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private let connection: Int32
    private let space: UInt64
    private let hideSpaces: SpacesFn
    private let destroySpace: SpaceFn
    private let addWindows: WindowsSpacesFn
    private let removeWindows: WindowsSpacesFn
    private let copySpaces: CopySpacesFn

    /// `level` é a altura absoluta do Space: 0 são os desktops do usuário; a tela de bloqueio fica
    /// bem acima (~300), então um valor baixo deixa o player sobre os apps e sob o bloqueio de tela.
    init?(level: Int) {
        guard let mainConnection = Self.symbol("MainConnectionID", as: MainConnectionFn.self),
              let create = Self.symbol("SpaceCreate", as: SpaceCreateFn.self),
              let setLevel = Self.symbol("SpaceSetAbsoluteLevel", as: SpaceLevelFn.self),
              let show = Self.symbol("ShowSpaces", as: SpacesFn.self),
              let hide = Self.symbol("HideSpaces", as: SpacesFn.self),
              let destroy = Self.symbol("SpaceDestroy", as: SpaceFn.self),
              let add = Self.symbol("AddWindowsToSpaces", as: WindowsSpacesFn.self),
              let remove = Self.symbol("RemoveWindowsFromSpaces", as: WindowsSpacesFn.self),
              let copy = Self.symbol("CopySpacesForWindows", as: CopySpacesFn.self)
        else { return nil }

        connection = mainConnection()
        // O flag precisa ser 1: com outros valores o Finder passa a desenhar os ícones da mesa nesse Space.
        space = create(connection, 1, nil)
        guard space != 0 else { return nil }
        hideSpaces = hide
        destroySpace = destroy
        addWindows = add
        removeWindows = remove
        copySpaces = copy
        setLevel(connection, space, level)
        show(connection, spaces)
    }

    deinit {
        hideSpaces(connection, spaces)
        destroySpace(connection, space)
    }

    /// Deixa a janela *só* no Space privado: se ela continuasse também nos desktops, voltaria a
    /// fazer parte da animação de troca.
    func pin(_ window: NSWindow) {
        let windows = [NSNumber(value: window.windowNumber)] as CFArray
        addWindows(connection, windows, spaces)
        // 0x7 = Spaces do usuário (desktops e apps em tela cheia); o privado não entra nessa máscara.
        if let desktops = copySpaces(connection, 0x7, windows)?.takeRetainedValue(), CFArrayGetCount(desktops) > 0 {
            removeWindows(connection, windows, desktops)
        }
    }

    func unpin(_ window: NSWindow) {
        removeWindows(connection, [NSNumber(value: window.windowNumber)] as CFArray, spaces)
    }

    private var spaces: CFArray { [NSNumber(value: space)] as CFArray }

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        if let pointer = dlsym(skyLight, "SLS" + name) ?? dlsym(defaultHandle, "CGS" + name) {
            return unsafeBitCast(pointer, to: type)
        }
        return nil
    }
}
