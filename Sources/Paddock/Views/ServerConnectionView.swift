import SwiftUI
import AppKit

struct ServerConnectionView: View {
    let details: ServerConnectionDetails
    let running: Bool
    let refresh: () -> Void
    @State private var copied: String?
    @State private var showPassword = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(text: "Данные для подключения")
                Spacer()
                Button("Обновить IP", action: refresh)
            }
            Text(details.configuration.name).font(.headline).textSelection(.enabled)
            if !running { Text("Сервер остановлен. Данные последнего запуска.").font(.caption).foregroundStyle(.orange) }
            addressRow("На этом Mac", address: details.localAddress)
            if details.addresses.isEmpty {
                Text("IP локальной сети не найден. Подключите Wi-Fi или Ethernet и нажмите «Обновить IP».").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(details.addresses) { address in
                addressRow("Для друзей в сети", address: details.endpoint(address.ip))
                Button("Скопировать приглашение · \(address.ip)") {
                    copy(details.invitation(ip: address.ip), label: "Приглашение скопировано")
                }
            }
            HStack(spacing: 20) {
                Text("HTTP: \(String(details.configuration.httpPort))")
                Text("Игра TCP/UDP: \(String(details.configuration.racePort))")
            }.font(.caption).monospacedDigit()
            Text("Машина: \(details.configuration.car) · Трасса: \(details.configuration.track)\(details.configuration.layout.isEmpty ? "" : " / " + details.configuration.layout)")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if details.configuration.password.isEmpty {
                Text("Пароль не требуется").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(showPassword ? "Пароль: \(details.configuration.password)" : "Пароль: ••••••••").font(.caption)
                    Button(showPassword ? "Скрыть" : "Показать") { showPassword.toggle() }
                    Button("Скопировать пароль") { copy(details.configuration.password, label: "Пароль скопирован") }
                }
                Text("Приглашение не содержит пароль; передайте его отдельно.").font(.caption).foregroundStyle(.secondary)
            }
            if let copied { Label(copied, systemImage: "checkmark").font(.caption).foregroundStyle(.green) }
            Text("В Paddock: Онлайн → Серверы → По адресу. Адреса выше относятся к этому Mac и его сети. Для интернета нужен внешний IP или адрес VPN и открытые порты; доступ извне автоматически не проверяется.")
                .font(.caption).foregroundStyle(.secondary)
        }.paddockPanel()
    }
    private func addressRow(_ title: String, address: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(address).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            }
            Spacer()
            Button("Скопировать адрес") { copy(address, label: "Адрес скопирован") }
                .accessibilityLabel("Скопировать адрес \(address)")
        }
    }
    private func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = label
    }
}
