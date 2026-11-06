import AppKit
import SwiftUI

struct RuntimeView: View {
    @ObservedObject var model: PaddockController
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel(text: "Среда запуска")
                Picker("Использовать", selection: $model.runtime) {
                    ForEach(LaunchRuntime.allCases) { Text($0.title).tag($0) }
                }.disabled(model.gameRunning || model.operation != nil)
                    .onChange(of: model.runtime) { _ in model.selectRuntime() }
                Text("Wine запускает вашу Steam-версию Assetto Corsa без подписки CrossOver. Руль, пресеты и рекорды работают через тот же мост MOZA.")
                    .font(.callout).foregroundStyle(.secondary)
            }.paddockPanel()
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel(text: "Независимый Wine")
                HStack {
                    Image(systemName: model.runtimeStatus?.prepared == true ? "checkmark.circle.fill" : "shippingbox")
                        .foregroundStyle(model.runtimeStatus?.prepared == true ? .green : .orange)
                    Text("Wine \(model.runtimeStatus?.version ?? "11.21")")
                    Spacer()
                    Text(model.runtimeStatus?.prepared == true ? "Среда подготовлена" : model.runtimeStatus?.installed == true ? "Нужна игра" : "Не установлен")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("1. Установите Wine.\n2. Перенесите Windows Steam с купленной игрой.\n3. Войдите в Steam и запускайте заезды со вкладки «Заезд».")
                    .font(.callout).foregroundStyle(.secondary).lineSpacing(6)
                HStack {
                    Button("Установить Wine") { model.installRuntime() }.disabled(model.runtimeStatus?.installed == true)
                    Button("Перенести Steam и игру") { model.prepareRuntime() }.disabled(model.runtimeStatus?.installed != true || model.runtimeStatus?.prepared == true)
                    Button("Выбрать папку Steam…") { model.prepareRuntime(chooseSource: true) }.disabled(model.runtimeStatus?.installed != true || model.runtimeStatus?.prepared == true)
                }
                Text("Создаётся независимая копия в Application Support/MozaPaddock. На APFS игровые файлы копируются клонированием. Текущий Steam и CrossOver остаются доступны.")
                    .font(.caption).foregroundStyle(.secondary)
                if let status = model.runtimeStatus { Text(status.prefix).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled) }
            }.paddockPanel().disabled(model.gameRunning || model.operation != nil)
            HStack {
                Button { model.openSteam() } label: { Label("Открыть Steam", systemImage: "play.desktopcomputer") }
                    .disabled(model.operation != nil || (model.runtime == .standalone && model.runtimeStatus?.prepared != true))
                Button("Проверить графику") { model.diagnoseRuntime() }
                    .disabled(model.gameRunning || model.operation != nil || (model.runtime == .standalone && model.runtimeStatus?.installed != true))
                Button("Журналы") { NSWorkspace.shared.open(model.paths.store) }
                Spacer()
                Button("Обновить статус") { model.refreshRuntimeStatus() }
            }
            Text("Для запуска на внешнем экране подключите монитор до старта Wine. Если Steam запрашивает вход, завершите его перед запуском игры.")
                .font(.caption).foregroundStyle(.secondary)
        }.onAppear { model.refreshRuntimeStatus() }
    }
}
