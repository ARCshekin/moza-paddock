import SwiftUI

struct OnlineView: View {
    @ObservedObject var model: PaddockController
    @ObservedObject var browser: OnlineBrowser
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Название сервера, машина или трасса", text: $browser.query).textFieldStyle(.roundedBorder)
                        .onSubmit { browser.refresh(paths: model.paths) }
                    Button("Найти") { browser.refresh(paths: model.paths) }.disabled(browser.loading)
                    if browser.loading { ProgressView().controlSize(.small) }
                }
                HStack {
                    TextField("Адрес или ссылка Content Manager · host:8081", text: $browser.directAddress).textFieldStyle(.roundedBorder)
                        .onSubmit { inspect(browser.directAddress) }
                    Button("По адресу") { inspect(browser.directAddress) }.disabled(browser.loading || browser.directAddress.isEmpty)
                }
                HStack {
                    Toggle("Есть места", isOn: $browser.onlyAvailable).toggleStyle(.checkbox)
                    Spacer()
                    Link("Каталог acservers.online", destination: URL(string: "https://acservers.online/servers")!)
                }.font(.caption).foregroundStyle(.secondary)
            }.paddockPanel()
            if let error = browser.error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if let server = browser.detail { details(server) }
            HStack {
                Text("Найдено: \(browser.total) · страница \(browser.page)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Назад") { browser.refresh(paths: model.paths, page: browser.page - 1) }.disabled(browser.loading || browser.page <= 1)
                Button("Далее") { browser.refresh(paths: model.paths, page: browser.page + 1) }.disabled(browser.loading || browser.page * 10 >= browser.total)
            }
            LazyVStack(spacing: 10) {
                ForEach(browser.servers.filter { !browser.onlyAvailable || $0.online && $0.clients < $0.capacity }) { server in
                    Button { inspect(server.id) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: server.password ? "lock.fill" : "network").foregroundStyle(server.online ? Color.green : Color.gray)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(server.name).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                                Text(server.track).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(server.clients)/\(server.capacity)").monospacedDigit()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).paddockPanel()
                    }.buttonStyle(.plain).disabled(browser.loading)
                }
            }
            Text("Список — снимок публичного каталога. Перед входом обновляются данные выбранного сервера. Сейчас доступны обычные pickup-серверы; бронирование и вход на CSP-серверы ещё в разработке.")
                .font(.caption).foregroundStyle(.secondary)
        }.onAppear { if browser.servers.isEmpty && !browser.loading { browser.refresh(paths: model.paths) } }
    }
    private func inspect(_ address: String) { browser.inspect(address, paths: model.paths, library: model.library) }
    private func details(_ server: OnlineServerDetails) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Подключение")
            HStack { Text(server.name).font(.headline); Spacer(); Text("\(server.latency) мс HTTP").font(.caption).foregroundStyle(.secondary) }
            if let (_, layout) = server.installedTrack(in: model.library) {
                Label(layout.name, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
            } else { Label("Трасса не установлена: \(server.track)", systemImage: "shippingbox").font(.caption).foregroundStyle(.orange) }
            if !server.missingCars(in: model.library).isEmpty {
                Text("Не установлены машины: " + server.missingCars(in: model.library).joined(separator: ", ")).font(.caption).foregroundStyle(.orange)
            }
            Picker("Машина", selection: $browser.car) {
                Text("Выберите машину").tag("")
                ForEach(server.cars, id: \.self) { id in
                    let asset = model.library.cars.first { $0.id == id }
                    Text("\(asset?.name ?? id) · мест: \(server.free[id] ?? 0)\(asset == nil ? " · не установлена" : "")").tag(id)
                }
            }
            HStack {
                TextField("Имя пилота", text: $browser.player).textFieldStyle(.roundedBorder)
                if server.password { SecureField("Пароль сервера", text: $browser.password).textFieldStyle(.roundedBorder) }
            }
            if server.csp { Text("Требуется CSP · подключение в этой версии пока недоступно").font(.caption).foregroundStyle(.orange) }
            if !server.pickup { Text("Требуется бронирование места").font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Обновить места") { inspect("\(server.host):\(server.httpPort)") }.disabled(browser.loading)
                Spacer()
                if model.gameRunning { Button("Завершить заезд") { model.stopGame() } }
                Button("Подключиться") {
                    let connection = OnlineConnection(server: server, car: browser.car, player: browser.player, password: browser.password)
                    model.launch(online: connection)
                    browser.password = ""
                }.buttonStyle(.borderedProminent)
                    .disabled(browser.loading || model.operation != nil || model.gameRunning || server.csp || !server.pickup ||
                              server.installedTrack(in: model.library) == nil || !server.missingCars(in: model.library).isEmpty || !model.library.cars.contains { $0.id == browser.car } || (server.free[browser.car] ?? 0) == 0)
            }
        }.paddockPanel()
    }
}
