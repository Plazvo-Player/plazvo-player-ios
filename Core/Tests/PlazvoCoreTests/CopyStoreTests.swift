import Foundation
import Testing
@testable import PlazvoCore

@Suite("Cópia guardada da última resposta do servidor")
struct CopyStoreTests {
    @Test("cópia em arquivo: guarda, lê, troca e apaga; fica fora das cópias de segurança")
    func fileCopy() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plazvo-teste-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        // A pasta ainda não existe: quem guarda a cópia a cria.
        let url = folder.appendingPathComponent("dentro").appendingPathComponent("site-answer.json")
        let store = FileCopyStore(url: url)

        #expect(store.read() == nil)

        store.write(Data("primeira".utf8))
        #expect(store.read() == Data("primeira".utf8))
        try expectLeftOutOfBackups(url)

        // Gravar de novo troca o arquivo por outro: a marca tem de valer no novo também.
        store.write(Data("segunda".utf8))
        #expect(store.read() == Data("segunda".utf8))
        try expectLeftOutOfBackups(url)

        store.delete()
        #expect(store.read() == nil)
        // Apagar o que não existe não é erro.
        store.delete()
        #expect(store.read() == nil)
    }

    @Test("arquivo vazio conta como cópia nenhuma")
    func emptyFileIsNoCopy() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plazvo-teste-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileCopyStore(url: folder.appendingPathComponent("site-answer.json"))

        store.write(Data())

        #expect(store.read() == nil)
    }

    @Test("cópia na memória: guarda, lê e apaga")
    func memoryCopy() {
        let store = InMemoryCopyStore()
        #expect(store.read() == nil)
        store.write(Data("texto".utf8))
        #expect(store.read() == Data("texto".utf8))
        store.delete()
        #expect(store.read() == nil)
    }

    /// Nos sistemas da Apple, o arquivo da cópia leva a marca de "fora das cópias de segurança".
    private func expectLeftOutOfBackups(_ url: URL) throws {
        #if canImport(Darwin)
        // Lido de novo do disco (um URL guarda o que já leu). Sistema que não informa a marca: nada a conferir.
        let fresh = URL(fileURLWithPath: url.path)
        if let excluded = try fresh.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup {
            #expect(excluded)
        }
        #endif
    }
}
