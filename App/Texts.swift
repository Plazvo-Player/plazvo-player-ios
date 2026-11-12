import Foundation
import PlazvoCore

/// Um texto do app, no idioma em uso (arquivos Localizable.strings), com `args` nos espaços (`%1$@`).
func t(_ key: String, _ args: String...) -> String {
    ScreenTexts.fill(NSLocalizedString(key, comment: ""), args)
}

/// O texto que a lógica escolheu para a situação, no idioma em uso.
func t(_ ref: TextRef) -> String {
    ScreenTexts.fill(NSLocalizedString(ref.key, comment: ""), ref.args)
}
