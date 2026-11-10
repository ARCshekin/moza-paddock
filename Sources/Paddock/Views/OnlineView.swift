import SwiftUI

struct OnlineView: View {
    @ObservedObject var model: PaddockController
    @ObservedObject var browser: OnlineBrowser
    @ObservedObject var lan: LANBrowser
    private var busy: Bool { browser.loading || browser.source == .lan && lan.loading }
    private var listedServers: [OnlineServer] { browser.source == .internet ? browser.servers : lan.servers }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Каталог серверов", selection: $browser.source) {
                ForEach(OnlineSource.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if browser.source == .lan {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Серверы локальной сети")
                    HStack {
                        TextField("Игровые UDP-порты · 9600-9610", text: $lan.ports).textFieldStyle(.roundedBorder)
                            .onSubmit { lan.refresh(paths: model.paths) }
                        Button("Найти в LAN") { lan.refresh(paths: model.paths) }.disabled(busy)
                        if lan.loading { ProgressView().controlSize(.small) }
                    }
                    Text("Поиск на этом Mac и через broadcast вашей сети. Для другого игрового порта измените диапазон; адрес и HTTP-порт также можно ввести ниже.").font(.caption).foregroundStyle(.secondary)
                    if let error = lan.error { Text(error).font(.caption).foregroundStyle(.orange) }
                }.paddockPanel()
            }
            VStack(alignment: .leading, spacing: 12) {
                if browser.source == .internet {
                    HStack {
                        TextField("Название сервера, машина или трасса", text: $browser.query).textFieldStyle(.roundedBorder)
                            .onSubmit { browser.refresh(paths: model.paths) }
                        Button("Найти") { browser.refresh(paths: model.paths) }.disabled(busy)
                        if browser.loading { ProgressView().controlSize(.small) }
                    }
                }
                HStack {
                    TextField("Адрес или ссылка Content Manager · host:8081", text: $browser.directAddress).textFieldStyle(.roundedBorder)
                        .onSubmit { inspect(browser.directAddress) }
                    Button("По адресу") { inspect(browser.directAddress) }.disabled(busy || browser.directAddress.isEmpty)
                }
                HStack {
                    Toggle("Есть места", isOn: $browser.onlyAvailable).toggleStyle(.checkbox)
                    Spacer()
                    if browser.source == .internet {
                        Link("Каталог acservers.online", destination: URL(string: "https://acservers.online/servers")!)
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }.paddockPanel()
            if let error = browser.favoritesError { Text(error).font(.caption).foregroundStyle(.orange) }
            if !browser.favorites.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Избранные серверы")
                    ForEach(browser.favorites) { favorite in
                        HStack {
                            Button { inspect(favorite.id) } label: {
                                VStack(alignment: .leading) {
                                    Text(favorite.name)
                                    Text(favorite.id).font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain).disabled(busy)
                            Spacer()
                            Button { browser.toggleFavorite(host: favorite.host, port: favorite.httpPort, name: favorite.name) } label: {
                                Image(systemName: "star.fill")
                            }.buttonStyle(.plain).accessibilityLabel("Убрать из избранного: \(favorite.name)")
                        }
                    }
                }.paddockPanel()
            }
            if let error = browser.error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if let server = browser.detail { details(server) }
            if browser.source == .internet {
                HStack {
                    Text("Найдено: \(browser.total) · страница \(browser.page)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Назад") { browser.refresh(paths: model.paths, page: browser.page - 1) }.disabled(busy || browser.page <= 1)
                    Button("Далее") { browser.refresh(paths: model.paths, page: browser.page + 1) }.disabled(busy || browser.page * 10 >= browser.total)
                }
            } else {
                Text("LAN-серверов: \(lan.servers.count)").font(.caption).foregroundStyle(.secondary)
                if lan.searched && lan.servers.isEmpty && !lan.loading {
                    Text("Серверы не найдены. Проверьте сеть и порты или введите IP вручную. Некоторые VPN и Wi-Fi с изоляцией клиентов не пропускают broadcast.").font(.caption).foregroundStyle(.secondary)
                }
            }
            LazyVStack(spacing: 10) {
                ForEach(listedServers.filter { !browser.onlyAvailable || $0.online && $0.clients < $0.capacity }) { server in
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
                    }.buttonStyle(.plain).disabled(busy)
                }
            }
            Text("Перед входом обновляются данные сервера. Сейчас доступны обычные pickup-серверы; бронирование и вход на CSP-серверы ещё в разработке.")
                .font(.caption).foregroundStyle(.secondary)
        }.onAppear { refreshSelected() }
            .onChange(of: browser.source) { _ in
                browser.sourceDidChange()
                refreshSelected()
            }
    }
    private func refreshSelected() {
        if browser.source == .internet {
            if browser.servers.isEmpty && !browser.loading { browser.refresh(paths: model.paths) }
        } else if !lan.searched && !lan.loading { lan.refresh(paths: model.paths) }
    }
    private func inspect(_ address: String) { browser.inspect(address, paths: model.paths, library: model.library) }
    private func details(_ server: OnlineServerDetails) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(text: "Подключение")
                Spacer()
                Button {
                    browser.toggleFavorite(host: server.host, port: server.httpPort, name: server.name)
                } label: {
                    Label(browser.isFavorite(host: server.host, port: server.httpPort) ? "Убрать из избранного" : "В избранное", systemImage: browser.isFavorite(host: server.host, port: server.httpPort) ? "star.fill" : "star")
                }
            }
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
                Button("Обновить места") { inspect("\(server.host):\(server.httpPort)") }.disabled(busy)
                Spacer()
                if model.gameRunning { Button("Завершить заезд") { model.stopGame() } }
                Button("Подключиться") {
                    let connection = OnlineConnection(server: server, car: browser.car, player: browser.player, password: browser.password)
                    model.launch(online: connection)
                    browser.password = ""
                }.buttonStyle(.borderedProminent)
                    .disabled(busy || model.operation != nil || model.gameRunning || server.csp || !server.pickup ||
                              server.installedTrack(in: model.library) == nil || !server.missingCars(in: model.library).isEmpty || !model.library.cars.contains { $0.id == browser.car } || (server.free[browser.car] ?? 0) == 0)
            }
        }.paddockPanel()
    }
}
