import PlazvoCore
import SwiftUI

/// Plazvo Player para iPhone e iPad.
/// Esta primeira versão só prova que o projeto compila e abre: uma tela com o nome do app,
/// uma linha que usa a lógica (pacote PlazvoCore) e uma linha que vem dos textos traduzidos.
@main
struct PlazvoPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            TelaDeTeste()
        }
    }
}

struct TelaDeTeste: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0x1B / 255, green: 0x17 / 255, blue: 0x38 / 255), location: 0),
                    .init(color: Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x14 / 255), location: 0.45),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                Text("Plazvo Player")
                    .font(.title.bold())
                    .foregroundColor(Color(red: 0xF1 / 255, green: 0xF1 / 255, blue: 0xF8 / 255))
                Text("Compilação de teste")
                    .font(.body)
                    .foregroundColor(Color(red: 0xA3 / 255, green: 0xA3 / 255, blue: 0xBD / 255))
                Text(DeviceIdGenerator.isValidKey("123456") ? "Lógica: ligada" : "Lógica: com defeito")
                    .font(.body)
                    .foregroundColor(Color(red: 0xA3 / 255, green: 0xA3 / 255, blue: 0xBD / 255))
                Text("playlists_inactive")
                    .font(.body)
                    .foregroundColor(Color(red: 0xA3 / 255, green: 0xA3 / 255, blue: 0xBD / 255))
            }
        }
    }
}
