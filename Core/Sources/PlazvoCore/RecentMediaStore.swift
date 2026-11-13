import Foundation

/// Guarda no aparelho os vídeos abertos recentemente e o ponto onde cada um parou.
/// Nada disso sai do aparelho. Use uma única instância por app.
@MainActor
public final class RecentMediaStore {
    /// Quantos vídeos a lista guarda.
    public static let maxItems = 20

    /// Do mais recente para o mais antigo.
    public private(set) var items: [RecentMedia] {
        didSet {
            if items != oldValue { onChange?(items) }
        }
    }

    /// Chamado a cada mudança da lista.
    public var onChange: (([RecentMedia]) -> Void)?

    private let storage: CopyStore
    private let now: () -> Date

    /// - Parameter storage: onde a lista fica guardada (os endereços de link podem ter senha: no
    ///   aparelho, um arquivo protegido e fora das cópias de segurança).
    public init(storage: CopyStore, now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.now = now
        items = RecentMediaStore.decode(storage.read())
    }

    public func find(_ uri: String) -> RecentMedia? {
        items.first { $0.uri == uri }
    }

    /// Põe o vídeo no topo da lista. Se já estava nela, mantém o ponto onde parou.
    public func markOpened(_ request: PlaybackRequest) {
        var entry = find(request.uri) ?? RecentMedia(uri: request.uri, title: request.title, kind: request.kind)
        entry.title = request.title
        entry.kind = request.kind
        entry.lastPlayedAt = Int64((now().timeIntervalSince1970 * 1000).rounded())
        if let access = request.access { entry.access = access }
        let all = [entry] + items.filter { $0.uri != request.uri }
        save(Array(all.prefix(RecentMediaStore.maxItems)))
    }

    /// Atualiza o ponto onde o vídeo parou. Não faz nada se o vídeo não estiver na lista.
    public func savePosition(_ uri: String, positionMs: Int64, durationMs: Int64) {
        guard let index = items.firstIndex(where: { $0.uri == uri }) else { return }
        var all = items
        all[index].positionMs = min(max(positionMs, 0), RecentMedia.maxTimeMs)
        all[index].durationMs = min(max(durationMs, 0), RecentMedia.maxTimeMs)
        save(all)
    }

    public func clear() {
        storage.delete()
        items = []
    }

    private func save(_ all: [RecentMedia]) {
        if let data = try? JSONEncoder().encode(all) {
            storage.write(data)
        }
        items = all
    }

    /// O que estava guardado. Dados estragados viram lista vazia (em vez de travar o app), e um
    /// item que não dá para ler, ou que o app nunca teria gravado, fica de fora.
    private static func decode(_ data: Data?) -> [RecentMedia] {
        guard let data, let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        var seen = Set<String>()
        var result: [RecentMedia] = []
        for entry in entries {
            guard result.count < maxItems, var item = entry.item, isStorable(item) else { continue }
            // O mesmo vídeo só aparece uma vez (vale o primeiro, o mais recente).
            guard seen.insert(item.uri).inserted else { continue }
            item.positionMs = min(max(item.positionMs, 0), RecentMedia.maxTimeMs)
            item.durationMs = min(max(item.durationMs, 0), RecentMedia.maxTimeMs)
            result.append(item)
        }
        return result
    }

    /// O app só grava arquivos do aparelho e links que ele mesmo aceitou em "Abrir link de vídeo".
    private static func isStorable(_ item: RecentMedia) -> Bool {
        switch item.kind {
        case .demo: return false
        case .file: return item.uri.hasPrefix("file://")
        case .link: return VideoLink.normalize(item.uri) == item.uri
        }
    }

    private struct Entry: Decodable {
        let item: RecentMedia?

        init(from decoder: Decoder) throws {
            item = try? RecentMedia(from: decoder)
        }
    }
}
