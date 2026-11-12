import Foundation

/// Arranjo da tela inicial conforme o tamanho da janela.
public enum HomeLayout: Equatable, Sendable {
    /// Celular em pé: tudo numa coluna.
    case compact
    /// Tablet em pé: a mesma coluna, com mais espaço.
    case medium
    /// Deitado ou tablet grande: a barra do alto numa linha só e o ID e a chave lado a lado.
    case wide
}

/// As contas do app Android para escolher o arranjo das telas (medidas em pontos).
public enum ScreenLayout {
    public static func home(width: Double, height: Double) -> HomeLayout {
        if width >= 840 || (width > height && width >= 560 && height >= 300) { return .wide }
        if width >= 600 { return .medium }
        return .compact
    }

    /// Tela larga das telas internas (Conta): o ID e a chave ficam lado a lado.
    public static func isWide(width: Double, height: Double) -> Bool {
        width >= 600 || (width > height && width >= 560 && height >= 300)
    }

    /// Celular estreito: na barra do alto da tela inicial, o logo, o nome e os botões ficam um
    /// pouco menores, para o nome não ser cortado.
    public static func isNarrowHeader(width: Double) -> Bool {
        width < 400
    }
}
