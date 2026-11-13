import Foundation
import PlazvoCore
import UniformTypeIdentifiers

/// O acesso aos vídeos neste aparelho: o vídeo de demonstração que vem dentro do app, o arquivo
/// que o usuário escolheu no seletor do sistema e o link.
///
/// O app não vê os arquivos do aparelho: recebe do sistema só o arquivo escolhido, com um
/// marcador para voltar a lê-lo depois (pela lista de recentes).
@MainActor
final class DeviceMediaAccess: MediaAccess {
    /// Os tipos de arquivo que o seletor deixa escolher: vídeos.
    static let videoTypes: [UTType] = {
        var types: [UTType] = [.movie, .video]
        // Formatos que o reprodutor toca e o sistema nem sempre conhece como vídeo.
        for name in ["mkv", "webm", "ts", "m2ts", "mts", "flv", "avi", "wmv", "mpg", "mpeg", "m4v", "mp4", "mov", "3gp", "vob", "ogv"] {
            if let type = UTType(filenameExtension: name), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }()

    /// Os arquivos escolhidos nesta abertura do app, pelo endereço: servem para o arquivo cujo
    /// marcador o sistema não entregou.
    private var chosen: [String: URL] = [:]
    /// O arquivo com o acesso aberto agora.
    private var inUse: URL?

    /// O que a lógica precisa para abrir o arquivo que o usuário escolheu no seletor do sistema.
    /// - Parameter untitled: o nome a mostrar se o arquivo vier sem nome.
    func picked(_ url: URL, untitled: String) -> (uri: String, title: String, access: Data?) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        // O marcador deixa o app reabrir o arquivo pela lista de recentes, mesmo depois de fechado.
        let access = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let uri = url.absoluteString
        chosen[uri] = url
        let name = url.lastPathComponent
        return (uri, name.isEmpty ? untitled : name, access)
    }

    func open(_ request: PlaybackRequest) -> String? {
        switch request.kind {
        case .demo:
            return Bundle.main.url(forResource: "demo_video", withExtension: "mp4")?.absoluteString
        case .link:
            return request.uri
        case .file:
            guard let url = fileURL(request) else { return nil }
            if url.startAccessingSecurityScopedResource() {
                inUse = url
            }
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                close()
                return nil
            }
            return url.absoluteString
        }
    }

    func close() {
        inUse?.stopAccessingSecurityScopedResource()
        inUse = nil
    }

    /// Onde o arquivo está agora: pelo marcador (que acompanha o arquivo se ele mudar de lugar),
    /// pelo arquivo escolhido nesta abertura do app ou, sem os dois, pelo endereço guardado.
    private func fileURL(_ request: PlaybackRequest) -> URL? {
        if let access = request.access {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: access, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url
            }
        }
        return chosen[request.uri] ?? URL(string: request.uri)
    }
}
