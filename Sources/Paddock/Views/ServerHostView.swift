import SwiftUI
import AppKit

struct ServerHostView: View {
    @ObservedObject var model: PaddockController
    @ObservedObject var host: ServerHost
    private var track: TrackAsset? { model.library.tracks.first { $0.id == host.draft.track } }
    private var maxSlots: Int { max(1, min(64, track?.layouts.first { $0.id == host.draft.layout }?.pits ?? 1)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !host.running {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(text: "Свой сервер · без обязательной аренды")
                    Text("Выберите машину и трассу — Paddock подготовит тренировку для друзей.").foregroundStyle(.secondary)
                    TextField("Название сервера", text: $host.draft.name).textFieldStyle(.roundedBorder)
                    Picker("Машина", selection: $host.draft.car) {
                        Text("Выберите машину").tag("")
                        ForEach(model.library.cars) { Text($0.name).tag($0.id) }
                    }
                    Picker("Трасса", selection: $host.draft.track) {
                        Text("Выберите трассу").tag("")
                        ForEach(model.library.tracks) { Text($0.name).tag($0.id) }
                    }
                    if let track {
                        Picker("Конфигурация", selection: $host.draft.layout) {
                            ForEach(track.layouts) { Text($0.name).tag($0.id) }
                        }
                    }
                    Stepper("Мест: \(host.draft.slots)", value: $host.draft.slots, in: 1...maxSlots)
                    SecureField("Пароль для друзей · необязательно", text: $host.draft.password).textFieldStyle(.roundedBorder)
                    DisclosureGroup("Дополнительно") {
                        VStack(alignment: .leading, spacing: 12) {
                            Stepper("Тренировка: \(host.draft.minutes) мин", value: $host.draft.minutes, in: 1...240)
                            Toggle("Публиковать в общем лобби", isOn: $host.draft.publicLobby)
                            HStack {
                                Text("Игра TCP/UDP"); TextField("9600", value: $host.draft.racePort, format: .number.grouping(.never)).frame(width: 90)
                                Text("HTTP"); TextField("8081", value: $host.draft.httpPort, format: .number.grouping(.never)).frame(width: 90)
                            }
                            Text("acServer.exe: \(host.executable?.path ?? "автоматическая установка из Steam-копии игры")").font(.caption).textSelection(.enabled)
                            Button("Выбрать acServer.exe…") { host.chooseExecutable() }
                        }.padding(.top, 10)
                    }
                }.paddockPanel().disabled(host.preparing)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(host.status, systemImage: host.running ? "network" : "server.rack")
                    Spacer()
                    if host.preparing { ProgressView().controlSize(.small) }
                }
                if let error = host.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                HStack {
                    if host.running {
                        Button(host.stopping ? "Останавливается…" : "Остановить") { host.stop() }.disabled(host.stopping)
                    } else {
                        Button("Создать и запустить") { host.start(paths: model.paths, library: model.library) }
                            .buttonStyle(.borderedProminent).disabled(host.preparing || model.operation != nil || host.draft.car.isEmpty || host.draft.track.isEmpty)
                    }
                    if let folder = host.folder {
                        Button("Файлы сервера") { NSWorkspace.shared.open(folder) }
                        Button("Журнал") { NSWorkspace.shared.open(folder.appendingPathComponent("server.log")) }
                    }
                }
                if host.connectionDetails == nil {
                    Text(host.connectionHint).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text("Подключение: Онлайн → По адресу. У друзей должны быть те же версии машины и трассы. Публикация в лобби сама по себе не открывает порты.").font(.caption).foregroundStyle(.secondary)
            }.paddockPanel()
            if let details = host.connectionDetails {
                ServerConnectionView(details: details, running: host.running, refresh: host.refreshConnectionAddresses).id(host.folder)
            }
            Text("Сервер автоматически устанавливается из вашей Steam-копии Assetto Corsa при сборке или первом запуске. Нужен бесплатный Wine из Настройки → Запуск. Первый старт создаёт отдельное окружение и может занять больше времени. Эта версия поддерживает одну машину с data.acd и обычную тренировку; CSP, трафик и чемпионаты пока не включены.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            if host.draft.car.isEmpty { host.draft.car = model.car?.id ?? model.library.cars.first?.id ?? "" }
            if host.draft.track.isEmpty { host.draft.track = model.track?.id ?? model.library.tracks.first?.id ?? ""; host.draft.layout = model.layout?.id ?? track?.layouts.first?.id ?? "" }
            host.draft.slots = min(host.draft.slots, maxSlots)
        }
        .onChange(of: host.draft.track) { _ in host.draft.layout = track?.layouts.first?.id ?? ""; host.draft.slots = min(host.draft.slots, maxSlots) }
        .onChange(of: host.draft.layout) { _ in host.draft.slots = min(host.draft.slots, maxSlots) }
    }
}
